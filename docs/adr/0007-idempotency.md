# ADR 0007: How reruns are made safe

- **Status:** accepted
- **Date:** 2026-11-16
- **Author:** group 7, Step 7 (orchestration)
- **Lesson:** L07

## Context

`marketplace_daily` runs every task more than once, and not only when something breaks.
This week alone, the same period ran again because of:

- **retries** (two per task, 5 minutes apart): `create_bronze_table` ran three times on
  2026-11-16 before its fix;
- **Clear**: the 2026-09-15 run was cleared and re-run after the fix;
- **back-fill**: 15 to 21 Sep, which overlapped a day that had already run;
- **overlap**: Airflow does not count back-fill runs against `max_active_runs`, so six
  back-fill runs and a scheduled run executed side by side.

So the question is never whether a task runs twice, but what happens when it does.

Three tasks write something. `dbt test`, when it runs separately, only reads.

| Task | Writes |
|---|---|
| `extract_orders` | Parquet in `gs://…/bronze/scheduled/orders/` |
| `create_bronze_table` | the definition of `g07_bronze.scheduled_orders` |
| `dbt_build` (or `dbt_run`) | views in `g07_silver`, tables in `g07_gold` |

Two constraints narrow the options:

- **Bronze is never overwritten.** `docs/architecture.md` promises that Bronze keeps every
  arrival and "never silently overwrite[s] prior arrival evidence".
- **BigQuery does not enforce uniqueness.** A primary key is metadata only, measured in
  lesson 7, so a constraint cannot be the mechanism.

## Options considered

| Option | Works when | Breaks when |
|---|---|---|
| Delete, then insert, by partition | the interval maps to one partition | an interval spans partitions, or the delete succeeds and the insert fails; and here it would overwrite Bronze |
| MERGE on a business key | you have a key you trust | the key is not unique, which lesson 5 taught us to test for; and Bronze is files, which have no MERGE |
| Write a new version, then swap to it | the data is small enough to keep both | storage grows with every version kept |
| Accept duplicates | never, here | always: lesson 4 showed what duplicates do to revenue |

## Decision

| Task | Mechanism | Why running it twice is safe | Chosen over |
|---|---|---|---|
| `extract_orders` | **New immutable version, newest wins at read time.** Each run writes a new object per day, `interval_date=D/load_id=L/part-0.parquet`, with a fresh `load_id` (a UTC timestamp). Nothing is overwritten. `stg_scheduled_orders` keeps only `max(load_id)` per `interval_date`. | A rerun adds a newer copy of the same day; silver shows exactly one. A failed run leaves the previous load in place, because each day's object is written whole or not at all. | Delete-then-insert by partition: it would break the Bronze promise, and a failure between the delete and the insert loses the day. |
| `create_bronze_table` | `CREATE OR REPLACE EXTERNAL TABLE` | It replaces a definition and reads no data; the result is the same however often it runs. | Creating it once by hand: then a fresh project would need an undocumented step. |
| dbt views (staging, intermediate) | `CREATE OR REPLACE VIEW` | A view stores no rows; replacing it twice gives the same view. | |
| dbt tables (marts) | `CREATE OR REPLACE TABLE` (dbt `table` materialisation) | BigQuery builds the new table and swaps it in atomically; readers see the old table or the new one, never a half-written one. | Incremental marts: ADR 0005 explains why the duplicate-order rule cannot be applied to new days only. |

The extract's mechanism is the "write a new version, then swap" option, with the swap done
by a view instead of a rename. Its cost is storage: every rerun keeps a copy of the day in
Bronze. At about 250 orders a day that is a few kilobytes, and the bucket's lifecycle rule
moves old objects to colder storage.

## Evidence

- **Rerun of one day** (2026-09-15, run three times, the last two successfully): Bronze
  holds **2 loads, 528 rows** (264 distinct orders); silver holds **1 load, 264 rows**,
  equal to the source.
- **Back-fill over a day that had already run** (15 to 21 Sep): silver equals the source on
  every day, 1,709 rows in all; Bronze holds 1,973. See `docs/orchestration.md`.
- **Unit tests**: `tests/test_ingestion.py`, class `IntervalExtractorTests`, checks that a
  rerun adds a load and refuses to overwrite one.

## The one we are least sure about

`extract_orders`, for three reasons:

1. **"Newest" is decided by the extracting machine's clock.** If two machines with skewed
   clocks extract the same day, the older extract could win. Today one machine runs the
   pipeline; a second operator would need clock checks, or a run id that orders reliably.
2. **A past day only changes if that day is rerun.** An order corrected in the source
   after its day was extracted stays as first extracted until somebody back-fills it. That
   is a limit of extracting by date, not of the rerun mechanism.
3. **An empty day hides behind an older full one.** If a day once had rows and is
   re-extracted with none (orders deleted in the source), the newest load is empty, so the
   view keeps showing the older rows. We have not seen it happen; it would need a marker
   row or a load table to fix.

The Step 3 cursor mode of the same script (not used by the DAG) is **not** idempotent: a
crash between upload and checkpoint repeats a batch. That is why the DAG uses the interval
mode.

## Consequences

- Easier: any task can be retried, cleared or back-filled without thinking first. The
  runbook's answer to "is it safe to re-run?" is yes, with one exception (a failed quality
  gate, which a rerun cannot fix).
- Harder: Bronze grows with every rerun, and reading it directly shows duplicates by
  design. Consumers read silver, never Bronze.
- To watch: the three risks above, and the bucket size under `bronze/scheduled/`.
