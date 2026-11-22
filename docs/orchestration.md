# Orchestration (Step 7)

The pipeline runs without a person: Airflow starts it every day, retries what fails,
tells a named person when something has failed for good, and stops before bad data reaches
the marts. Everything below was run on 2026-11-16, on the operator's laptop (8 GB of RAM).

## The DAG

[`orchestration/dags/marketplace_daily.py`](../orchestration/dags/marketplace_daily.py):

```text
extract_orders  ->  create_bronze_table  ->  dbt_build   (the quality gate)
```

| Task | Runs | Does |
|---|---|---|
| `extract_orders` | `omara11/group7-ingestion:2026-11-17-e8df6e5` | orders whose `order_date` is in the run's period, and their lines, from the source database to `bronze/scheduled/order_items/` and `bronze/scheduled/orders/` |
| `create_bronze_table` | `omara11/group7-transform:2026-11-22-c565e73` | `dbt run-operation create_scheduled_orders_table`: the two external tables over those paths |
| `dbt_build` | the same transform image | `dbt build`: every model, each tested as it is built |

- **Every task is a `DockerOperator`** running a Step 6 image beside Airflow, through the
  mounted Docker socket. Each image is named in one place in the DAG file (ADR 0006).
- **The period comes from the run.** The DAG sets `INTERVAL_START` and `INTERVAL_END` to
  `{{ data_interval_start | ds }}` and `{{ data_interval_end | ds }}`, and the extractor
  reads them. Nothing in the pipeline calls the clock to decide what to read.
- **Schedule:** daily, from 2026-09-15, `catchup=False`, `max_active_runs=1`. The DAG uses
  `CronDataIntervalTimetable("0 0 * * *")` instead of `"@daily"`. In Airflow 3.3.2 a plain
  `"@daily"` gave runs with no interval: rendering a run showed `INTERVAL_START` and
  `INTERVAL_END` both `2026-09-16`, an empty period.
- **Structure only:** the file imports no pandas and queries nothing at import time.
- **The gate has two modes**, chosen by `G07_GATE` in `orchestration/.env`. `lock` (the
  default) is `dbt build`. `alarm` is `dbt run` then `dbt test`, kept only so the fire drill
  below can show both.

## Set-up on a new machine

From the repository root, with Docker Desktop running:

1. Start the source database (the first time it downloads and restores the dataset):
   `docker compose up -d migrate`
2. Log in to Google (`gcloud auth application-default login`), then copy the credentials
   into the volume the tasks mount read-only. They never enter an image:

   ```powershell
   docker volume create g07_gcloud
   docker run --rm --user 0 -v g07_gcloud:/gcp -v "$env:APPDATA\gcloud\application_default_credentials.json:/src/adc.json:ro" python:3.12.12-slim-bookworm sh -c "cp /src/adc.json /gcp/application_default_credentials.json && chmod 644 /gcp/application_default_credentials.json"
   ```

3. Start Airflow: `docker compose -f orchestration/compose.yaml up -d`. The UI is at
   http://localhost:8080 (user `airflow`, password `airflow`, local only).
4. Unpause the DAG once. New DAGs start paused, and this is the only manual step:
   `docker compose -f orchestration/compose.yaml exec airflow-scheduler airflow dags unpause marketplace_daily`

**Memory, measured:** the lean stack (`LocalExecutor`: database, API server, scheduler and
DAG processor; no Redis, Celery worker or triggerer) used about **0.8 GB** idle and about
**1 GB** while tasks ran, inside Docker's 3.7 GiB.

## Idempotency: why running a task twice is safe

The decision behind this table is [ADR 0007](adr/0007-idempotency.md).

| Task | What it writes | Why running it twice is safe |
|---|---|---|
| `extract_orders` | `gs://…/bronze/scheduled/{order_items,orders}/interval_date=D/load_id=L/part-0.parquet`, lines first | **A new immutable load per run; the newest load wins at read time.** Nothing is overwritten. `stg_scheduled_orders` keeps only `max(load_id)` per day, and `stg_scheduled_order_items` only the lines of that load. |
| `create_bronze_table` | definitions of `g07_bronze.scheduled_orders` and `scheduled_order_items` | **`CREATE OR REPLACE EXTERNAL TABLE`**: replaces a definition and reads no data |
| `dbt_build` / `dbt_run` | views in `g07_silver`, tables in `g07_gold` | **`CREATE OR REPLACE VIEW` / `CREATE OR REPLACE TABLE`**: BigQuery swaps the new table in atomically |
| `dbt_test` | nothing | it only reads |

Not a mechanism we rely on: the primary key. BigQuery does not enforce it.

**Measured:** 2026-09-15 ran three times (the last two successfully). Bronze holds **2
loads, 528 rows** for that day, and silver holds **1 load, 264 rows**, equal to the source.

## Retries and the failure alert

- **Retries:** 2 per task, **5 minutes apart**, with a 30-minute timeout. Five minutes is
  longer than anything we retry: a dropped connection or a BigQuery hiccup clears in
  minutes, and quick retries would only produce three failures instead of one.
- **Alert:** `on_failure_callback`, which fires once a task has failed for the last time.
  It writes one line to **`orchestration/logs/alerts/failures.log`** (and posts it to
  `G07_ALERT_WEBHOOK` if one is set). Not `on_retry_callback`, which would fire on every
  attempt.
- **Who sees it:** Omar Abdellatif reads the alert log. **What to do:** follow
  [the runbook](runbooks/failed-run.md).

### Evidence: the first failure was real

The first runs failed on a real bug. The external-table macro used a `labels` option that
BigQuery rejects (`Database Error: Unknown option: labels`). `create_bronze_table` failed on
all three attempts, `dbt_build` was skipped (`upstream_failed`), and the alert log received
**exactly one line per run, for try 3 only**. Nothing was written for tries 1 and 2:

```text
{"at": "2026-11-16T15:41:45.254841+00:00", "dag": "marketplace_daily", "task": "create_bronze_table", "period": "2026-09-15", "try": 3, "message": "[g07 pipeline FAILED] dag=marketplace_daily task=create_bronze_table period=2026-09-15 try=3 log=http://localhost:8080/dags/marketplace_daily/runs/backfill__2026-09-16T00%3A00%3A00%2B00%3A00/tasks/create_bronze_table?try_number=3"}
{"at": "2026-11-16T15:41:45.425345+00:00", "dag": "marketplace_daily", "task": "create_bronze_table", "period": "2026-11-15", "try": 3, "message": "[g07 pipeline FAILED] dag=marketplace_daily task=create_bronze_table period=2026-11-15 try=3 log=http://localhost:8080/dags/marketplace_daily/runs/scheduled__2026-11-16T00%3A00%3A00%2B00%3A00/tasks/create_bronze_table?try_number=3"}
```

The fix was a new commit, a new transform image (`2026-11-16-9ddc0f1`) and a rerun, which
went green in 99 seconds.

Not explained: the second attempt started at 11:55, but the third ended at 15:41, while
three attempts 5 minutes apart should take about 15 minutes. The laptop or Docker most
likely slept in between, but that is not confirmed. Later runs kept to the expected timing.

## The quality gate, and proof that it stops the pipeline

### The poison row

One extra Parquet file was written into the orders snapshot that gold reads,
`bronze/snapshot/orders/ingestion_date=2026-10-26/load_id=20261026T105159Z-2efcb86a/zz-step7-drill-poison.parquet`.
It holds a single row, a copy of **order 8**, so that `order_id` appears twice. It was
designed against `unique` on `stg_orders.order_id`. Bronze then held 222,645 orders, with
order 8 twice.

Baseline before the poison: `fct_order_items` had **204,280** rows and **693,320** units,
and order 8 had 3 lines, 10 units and €275.10.

### Phase 1: alarm (`dbt run`, then `dbt test`), run for 2026-09-22

| | Before | After `dbt_run` | After the run ended |
|---|---:|---:|---:|
| `fct_order_items` rows | 204,280 | **204,283** | **204,283** |
| units in `fct_order_items` and `fct_daily_demand` | 693,320 | **693,330** | **693,330** |

- `dbt_run` **succeeded** and rebuilt the marts from the poisoned Bronze.
- `dbt_test` then failed all three attempts, and the run went red. The failing tests were
  `unique_stg_orders_order_id` and the two duplicate-order tests from Step 5,
  `assert_dedup_halves_orders` and `assert_twin_groups_are_even`
  (`PASS=68 WARN=1 ERROR=3`).
- The alert arrived, once, on try 3:

  ```text
  {"at": "2026-11-16T18:02:39.700593+00:00", "dag": "marketplace_daily", "task": "dbt_test", "period": "2026-09-22", "try": 3, "message": "[g07 pipeline FAILED] dag=marketplace_daily task=dbt_test period=2026-09-22 try=3 log=http://localhost:8080/dags/marketplace_daily/runs/backfill__2026-09-23T00%3A00%3A00%2B00%3A00/tasks/dbt_test?try_number=3"}
  ```

- **The bad number reached the marts, and stayed there after the run went red.** Gold
  gained 3 lines and 10 units. They were not more rows for order 8, but for **order
  111330**, order 8's twin. The extra copy made the twin group odd, so the duplicate-order
  rule kept both twins: the double count Step 1 warned about.

This gate was an **alarm**: it reported the problem after the marts already held it.

Between the phases the poison was deleted and the marts rebuilt cleanly (`dbt build`,
`PASS=89 WARN=1 ERROR=0`), back to 204,280 rows and 693,320 units.

### Phase 2: lock (`dbt build`), run for 2026-09-23

The same poison file was written again, the gate switched back to `dbt build` (the
default), and one run started.

| | Before | After the run ended |
|---|---:|---:|
| `fct_order_items` rows | 204,280 | **204,280** |
| units in `fct_order_items` and `fct_daily_demand` | 693,320 | **693,320** |
| `fct_order_items` last rebuilt | 18:06:37 UTC | **18:06:37 UTC** (not rebuilt) |

- `dbt_build` failed all three attempts, and the run went red
  (`PASS=61 WARN=1 ERROR=2 SKIP=26`). The two failing tests were
  `unique_stg_orders_order_id` and `assert_twin_groups_are_even`.
- Because a test on `stg_orders` failed, dbt **skipped everything downstream of it**:
  `g07_silver.int_orders_deduplicated`, `g07_gold.fct_order_items`,
  `g07_gold.fct_daily_demand` and their tests.
- The alert arrived, once, on try 3:

  ```text
  {"at": "2026-11-16T18:25:57.729992+00:00", "dag": "marketplace_daily", "task": "dbt_build", "period": "2026-09-23", "try": 3, "message": "[g07 pipeline FAILED] dag=marketplace_daily task=dbt_build period=2026-09-23 try=3 log=http://localhost:8080/dags/marketplace_daily/runs/backfill__2026-09-24T00%3A00%3A00%2B00%3A00/tasks/dbt_build?try_number=3"}
  ```

- **The bad number did not reach the marts.** Gold kept its last good numbers and was not
  even rebuilt, while the run was red and the alert pointed at the failed test.

This gate is a **lock**. It is the DAG's default, and the alarm shape is kept only for
this drill.

### Why the two phases failed different tests

In the alarm phase `dbt test` ran every test, including `assert_dedup_halves_orders`,
which reads the already-rebuilt intermediate model. In the lock phase that model was
skipped, so the test that depends on it was skipped too. Two tests caught the poison
before anything was built from it.

### Clean-up

The poison file was deleted from Bronze. (The bucket's 7-day soft delete keeps a copy, but
no table reads it.) The two red drill runs were then cleared and re-run without it: both
went green in 106 seconds, and gold was back to **204,280** rows and **693,320** units.
The 2026-09-22 run now shows `dbt_build` instead of `dbt_run` and `dbt_test`, because a
rerun uses the DAG's current shape. Every run of the DAG ended `success`, and the alert log
holds exactly four lines: two from the `labels` bug and one from each drill phase.

## Back-fill

### Range and prediction (written before running)

Range: **2026-09-15 to 2026-09-21**, seven daily runs of `marketplace_daily`.

The prediction comes from the source database itself, read on 2026-11-16 with the load
generator stopped (so the numbers cannot move):

```sql
select order_date, count(*) from public.orders
where order_date >= date '2026-09-15' and order_date < date '2026-09-22'
group by 1 order by 1;
```

| Day | Orders in the source |
|---|---:|
| 2026-09-15 | 264 |
| 2026-09-16 | 242 |
| 2026-09-17 | 244 |
| 2026-09-18 | 243 |
| 2026-09-19 | 224 |
| 2026-09-20 | 235 |
| 2026-09-21 | 257 |
| **Total** | **1,709** |

What the back-fill should do, given that a run for 2026-09-15 already exists (it ran
twice already, and Airflow's default back-fill does not reprocess existing runs):

- `--dry-run` lists **7** dates, and the real back-fill creates **6** new runs (16 to 21 Sep).
- Bronze gains **6** new loads holding **1,445** rows (242 + 244 + 243 + 224 + 235 + 257).
  15 Sep keeps its two earlier loads (2 × 264 = 528 rows), so Bronze holds **1,973** rows
  for the week.
- Silver (`stg_scheduled_orders`) holds **one** load per day and **1,709** rows for the
  week, equal to the source.
- Every run green; no line added to the alert log.

### Actual (run on 2026-11-16)

The dry run, before anything was created:

```text
PS> airflow backfill create --dag-id marketplace_daily --from-date 2026-09-15 --to-date 2026-09-21 --dry-run
    - reprocess_behavior = None
    - run_on_latest_version = True
Runs to be attempted:
| logical_date              |
| 2026-09-16 00:00:00+00:00 |
| 2026-09-17 00:00:00+00:00 |
| 2026-09-18 00:00:00+00:00 |
| 2026-09-19 00:00:00+00:00 |
| 2026-09-20 00:00:00+00:00 |
| 2026-09-21 00:00:00+00:00 |
```

(Table borders and the empty partition columns are trimmed.) Then the real back-fill,
with the same arguments and no `--dry-run`. All six runs ended `success`, and no line was
added to the alert log. Read from BigQuery afterwards:

| Day | Predicted | Bronze loads | Bronze rows | Silver loads | Silver rows | Silver = prediction |
|---|---:|---:|---:|---:|---:|---|
| 2026-09-15 | 264 | 2 | 528 | 1 | 264 | yes |
| 2026-09-16 | 242 | 1 | 242 | 1 | 242 | yes |
| 2026-09-17 | 244 | 1 | 244 | 1 | 244 | yes |
| 2026-09-18 | 243 | 1 | 243 | 1 | 243 | yes |
| 2026-09-19 | 224 | 1 | 224 | 1 | 224 | yes |
| 2026-09-20 | 235 | 1 | 235 | 1 | 235 | yes |
| 2026-09-21 | 257 | 1 | 257 | 1 | 257 | yes |
| **Total** | **1,709** | | **1,973** | | **1,709** | **yes** |

### Where the prediction was wrong, and why

- **The dry run listed 6 dates, not the 7 predicted.** `--dry-run` already leaves out
  dates that have a run (15 Sep had one), so it lists only what it will create. The
  prediction assumed it would list the whole range and skip later.
- Everything else matched exactly: 6 new runs, 1,445 new Bronze rows, 1,973 Bronze rows
  and 1,709 silver rows for the week.
- **Not predicted, and worth knowing:** the six back-fill runs ran side by side (two
  tasks at a time, the `parallelism` setting), not one after another. Airflow does not
  count back-fill runs against `max_active_runs`. Because every task is idempotent, this
  was harmless here.

Run ids are named after the moment a run is due, which is the end of its period: the run
`backfill__2026-09-22T00:00:00+00:00` covers 2026-09-21.

### The silent run

The scheduled run for 2026-11-15 (no orders exist that day) ended `success` and wrote one
empty file, so Bronze has 0 rows for that day. That is the third drill of lesson 7: a
period with no data goes green. Nothing in the pipeline says "there was nothing", and the
section on alerts below explains what would.

## The scheduled orders reach gold (review fix, 2026-11-17)

The first review of this step found the main gap: the scheduled orders reached silver
(`stg_scheduled_orders`) but nothing read them, so gold still showed only the Step 2
snapshot. Fixed as follows (decisions taken by Omar on 2026-11-17):

- **The extract also takes the order lines.** A line-grain fact needs products,
  quantities and prices, which `public.orders` does not hold. Each run now writes the
  day's `order_items` under the same `load_id`, lines first, so an orders load always has
  its lines (`ingestion/README.md`).
- **Gold switches source on one date.** `int_order_lines` takes the deduplicated snapshot
  before `scheduled_orders_from` (2026-09-15, in `dbt_project.yml`) and the scheduled
  extract from that day. The snapshot's last order is 2026-09-14 and the two share no
  `order_id` (checked: 0 overlaps), so no order is counted twice. `fct_order_items` says
  which with `order_origin`.
- **No twin rule on the new orders.** The duplicates are a defect of the legacy snapshot.
  In the local source, 18 payment ids are shared by two orders of the same buyer since 15
  September, and all 18 have different baskets: real repeat purchases, which the rule would
  have dropped. `assert_dedup_halves_orders` still checks the snapshot, unchanged.
- **UNKNOWN country.** 46 of the first 2,208 new orders come from buyers with no address
  in the snapshot (45 of them have none in the source either). They land in a new
  `UNKNOWN` member of `dim_country` instead of being dropped or failing the build, as the
  design sketch planned (acceptance criteria, D2).
- **A test that a new order reaches gold.** `assert_scheduled_orders_reach_gold` fails the
  build if any scheduled order in silver is missing from `fct_order_items`, has no lines,
  or gains or loses a line or a unit on the way. `assert_reconciled_lines_preserved` now
  counts both origins.

### Evidence

1. **Re-extract of 15-23 Sep** with the new ingestion image, so every day's newest load has
   its lines: 2,208 orders and 4,140 lines, 18 objects, load `20261117T162655908663Z`.
   `dbt build`: `PASS=102 WARN=1 ERROR=0` (the warning is the 6 unnamed products).
2. **Gold equals silver on every day, 15-23 Sep** (orders per day: 264, 242, 244, 243,
   224, 235, 257, 256, 243). The snapshot part did not move: 111,322 orders, 204,280
   lines, 693,320 units.
3. **A day gold had never seen, through the DAG.** Before the run, gold had no order on
   2026-09-24. The back-fill run for that day (`backfill__2026-09-25T00:00:00+00:00`) went
   green in under 3 minutes: `extract_orders`, `create_bronze_table`, `dbt_build`. Gold then
   held exactly the 4 source orders of that day (224898 to 224901), with the same products
   and quantities as the source, and `fct_daily_demand` ran to 2026-09-24.

| `fct_order_items` | Orders | Lines | Units | UNKNOWN-country lines |
|---|---|---|---|---|
| snapshot (to 2026-09-14) | 111,322 | 204,280 | 693,320 | 0 |
| scheduled (2026-09-15 to 24) | 2,212 | 4,144 | 14,019 | 70 |

`fct_daily_demand` sums to 707,339 units, the two rows added together.

Runs 1 to 3 used local builds of commit `71219f3`. The published images,
`omara11/group7-ingestion:2026-11-17-e8df6e5` and `omara11/group7-transform:2026-11-17-e8df6e5`
(the same code plus the Step 6 review fix, `uv sync --locked`), are the DAG's defaults. The
24 Sep run was cleared and rerun on them: all three tasks green, `PASS=102 WARN=1 ERROR=0`.
A rerun of a day changes nothing in gold, as the idempotency table says.

On 2026-11-22 the transform default moved to `omara11/group7-transform:2026-11-22-c565e73`, built by Omar from commit
`c565e73` (digest `sha256:ebbea9ef3cd7d2e5cf490a2d00f107bfc94004856cb9e7ebbc72662c8c971ba8`). It adds `selectors.yml`, which the DAG's
`--selector` needs, and the `buyer_id` policy tag (Step 10). Omar checked it offline with
`dbt ls`. **It has not yet run against BigQuery:** the first DAG run on it is the check.
The ingestion image is unchanged.
