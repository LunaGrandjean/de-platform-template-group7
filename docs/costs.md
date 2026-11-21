# Bronze storage and operations cost baseline

Price lookup date: **2026-10-26**. Currency: USD, before tax, credits or negotiated
discounts. Scope: `gs://data-engineering-i1-marketplace-group`, a single-region,
flat-namespace GCS bucket in `europe-west1`, initially using Standard storage.
This is a model based on measured bytes, not an actual billing export.

## Published price references

Use the [Google Cloud Storage pricing page](https://cloud.google.com/storage/pricing)
with Belgium (`europe-west1`) selected. The Standard reference rate used is
**$0.020/GiB-month** (approximately $0.000027397/GiB-hour for a 730-hour month).
The regional flat-namespace operation rates are **$0.005 per 1,000 Class A**
operations and **$0.0004 per 1,000 Class B** operations.

The estimate includes stored bytes, initial object writes and one object read
per day for 30 days. It excludes BigQuery queries/storage, network transfer,
additional metadata/list requests and retries. No GCS free-tier discount is
assumed for this European region. Refresh prices before using this baseline for
a budget decision; a browser's default region may display Iowa instead of Belgium.

## Measured inventory

The [landing manifest](evidence/step2/landing-manifest.json),
[upload receipt](evidence/step2/upload-receipt.json) and actual
[GCS inventory](evidence/step2/inventory.json) establish:

- 7 tables, 1,296,708 rows and 19 Parquet objects.
- Parquet storage: 60,949,265 bytes.
- One completion-manifest object: 9,208 bytes, measured in GCS.
- Baseline total: **60,958,473 bytes** (about 0.05677 GiB), **20 objects**.

The inventory represents one completed snapshot. Existing classroom-exercise
buckets and future automated ingestion are outside this group's baseline.

## One-month model and 100x growth

Assumptions: retain one snapshot for a month in Standard, write each object
once, and read each object once per day. The 100x case scales bytes **and object
counts** by 100, representing 100 snapshot-equivalents at the same file shape;
it is a scenario, not an observed deployment.

```text
storage = total_bytes / 2^30 * 0.020
initial_writes = object_count / 1000 * 0.005
monthly_reads = object_count * 30 / 1000 * 0.0004
first_month = storage + initial_writes + monthly_reads
```

| Item | Current snapshot | 100x scenario |
|---|---:|---:|
| Retained bytes | 60,958,473 | 6,095,847,300 |
| Objects | 20 | 2,000 |
| Monthly storage | $0.001135 | $0.113544 |
| Initial Class A writes (one-time) | $0.000100 | $0.010000 |
| Class B reads over 30 days | $0.000240 | $0.024000 |
| **First-month model total** | **$0.001475** | **$0.147544** |

Initial writes are not a recurring monthly charge if no new data is written.
A snapshot added every day would accumulate roughly 30 snapshot-equivalents
after a month; it must not be budgeted as one static snapshot. Real operations
also include the bucket creation/inspection, IAM lookups, checksums and metadata
verification used during setup. Their counts were not captured as billing
metrics, so the table estimates the steady object workload rather than the
exact cost of this session.

## Lifecycle and cost limits

The [applied lifecycle](../infra/lifecycle.json) moves `bronze/` objects to
Nearline at age 30 days, Coldline at 90 days and Archive at 365 days. It contains
no deletion action. The table above models the initial Standard month only;
do not extrapolate its read price to colder classes.

Colder classes have retrieval charges and minimum storage durations. Each
lifecycle transition also incurs an operation at the destination class's rate.
The bucket's seven-day soft-delete policy can retain charged bytes after
deletion, although this pipeline performs no deletes. Review these factors
before changing retention or replaying archived snapshots. See the published
[storage-class conditions](https://cloud.google.com/storage/docs/storage-classes)
and [lifecycle behaviour](https://cloud.google.com/storage/docs/lifecycle).

Step 4 adds selected native BigQuery working tables; see [warehouse tuning](warehouse-tuning.md)
for three processed-byte query costs and the per-query cap, and the
[pricing ADR](adr/0004-warehouse-pricing.md) for capacity crossover.
The initial approximately 33 MB of native logical storage is small; free-tier
availability is shared and has not been audited for this billing account. Later FinOps work will compare this model with actual usage and
revisit file sizes, refresh frequency and long-term retention.

---

# Step 9: attributable, and one saving measured

Measured on **2026-11-19** by Anas Mossad. Prices: Belgium (`europe-west1`) list
prices read on 2026-11-19 ([pricing evidence](evidence/step9/pricing-2026-11-19.json)),
USD before tax and credits. Every figure below says whether it was measured
(bytes, objects, jobs) or calculated (dollars, from the measured units).

## 1. Label convention

Four keys, the same on every Terraform resource that takes labels, on every
table and view dbt builds, and on every BigQuery job dbt and
`scripts/warehouse.py` run:

| Key | Values | Why it exists |
|---|---|---|
| `group` | `g07` | **Who pays.** `data-engineering-i1` is shared by every group of the course (26 people ran queries in it this month). Without this key our lines cannot be told apart from another group's. Kept as `group`, not `team`: the course, our dataset names and the existing dbt labels already say `g07`. |
| `env` | `dev`, `prod` | So a test spike is never read as production. One environment today; the key costs nothing and stops a future `prod` being mixed in silently. |
| `layer` | `bronze`, `warehouse`, `silver`, `gold` (`none` on jobs that write no table) | **What drives the cost.** Each layer has a different driver: Bronze is GCS bytes and object operations, warehouse and gold are stored tables, silver is views (no storage, only the bytes scanned through them). It matches ADR 0001. |
| `component` | `ingestion`, `warehouse`, `dbt`, `terraform` | **Who to ask.** The code that writes into the resource or runs the job. A cost on `component=dbt` goes to whoever owns `transform/`. |

Jobs also carry `resource` (`model`, `test`, `operation`, set by dbt), so a build
splits into building and testing. That split is how the saving in section 5 was
found.

Dropped in Step 9: `step` (`l04`, `l05`) said *when* a resource was made, not
who pays, and git already records that. `application` and `managed-by` on the
bucket said neither.

**Where it is applied, and how:**

- **Terraform** ([`labels.tf`](../infra/terraform/labels.tf)): `group` and `env`
  as the provider's `default_labels`, so no resource can be declared without
  them; `layer` and `component` on each resource in
  [`main.tf`](../infra/terraform/main.tf). The bucket and the four datasets carry
  all four.
- **dbt** ([`dbt_project.yml`](../transform/dbt_project.yml)): all four on every
  table and view, and on every **job** through `query-comment` with
  `job-label: true` ([`g07_query_comment`](../transform/macros/g07_query_comment.sql)).
  Checked on a real job on 2026-11-19: `group=g07, env=dev, component=dbt`
  ([evidence](evidence/step9/job-labels-check.json)).
- **`scripts/warehouse.py`**: the same keys on its datasets and tables, and on
  its jobs through the client's default job config.

**Job labels matter more than resource labels here.** BigQuery bills a query to
the job that ran it, not to the dataset it read. Labelling `g07_gold` says
whose storage it is; it says nothing about who spent the bytes reading it. Our
largest cost (section 4) is queries, so without job labels the convention would
have attributed the small lines and left the big one blank.

**What carries no label, and why:**

- The 12 dataset IAM bindings, the (uncreated) `g07-pipeline` service account
  and its bindings (Bronze object user, bucket metadata reader, editor on all four
  datasets; `service_account.tf`, all `count = 0` today): these resource
  types take no labels in GCP, and cost nothing.
- The Terraform state bucket: outside Terraform on purpose (ADR 0008). It was
  labelled by hand on 2026-11-08 with an older set (`group`, `layer`, `lesson`,
  `managed-by`). 37.6 KB, effectively free.
- Queries a member types in the BigQuery console or a notebook: no code sets
  their labels. They can only be attributed afterwards, by user and dataset.
- The two scheduled external tables in `g07_bronze`: BigQuery rejects `labels`
  in `CREATE EXTERNAL TABLE` (Step 7). They store nothing; the jobs that read
  them are labelled.

**Labels only apply from the moment they are set.** They never relabel a
billing line that already exists. Everything group 7 spent **before
2026-11-19 is unattributable by label, and will stay that way**: 25.1 GiB of
query bytes ran with no `group` label (dbt jobs carried only
`dbt_invocation_id`, `scripts/warehouse.py` jobs nothing), `g07_silver` and
`g07_gold` had no labels at all, and the bucket had no `group`. The figures in
sections 4 and 5 are ours only by inference: jobs that read or wrote a `g07_*`
dataset, run by one of our five members. That is a heuristic, not
attribution. A job of ours that touched no `g07_*` table is missing from it.

## 2. Budget alert

[`budget.tf`](../infra/terraform/budget.tf) declares a monthly budget of **10
(in the billing account's currency) on spend labelled `group=g07`**, with
thresholds at 50%, 90%, 100% and 100% of forecast, sent by email to **Anas
Mossad** (`budget_alert_email`) and nobody else
(`disable_default_iam_recipients`). It is scoped by label, not by project,
because a project budget would fire on the other groups' spend.

**This budget does not stop anything: it sends an email, and above 100% it
sends nothing more. It does not refuse a query, pause the DAG or disable
billing.** What actually refuses spend is the per-query cap: the 1 GB
`maximum_bytes_billed` in dbt and in `scripts/warehouse.py` (Step 4), which
fails a runaway query before it runs.

**Status: declared, not created.** A budget lives on the billing account. The
Cloud Billing API is disabled in `data-engineering-i1`, and our identities get
`403 SERVICE_DISABLED` reading the project's billing info
([evidence](evidence/step9/billing-access.json)). So we can neither find the
account ID nor create a budget on it. The resources have `count = 0` until
`billing_account_id` is set. Asked of the course admin: either the account ID
plus `billing.budgets.create`, or creating the same budget from `budget.tf`.
Until then the only alarm is the course's own project budget, which reaches
the admin, not us. Even once created, it only counts spend from 2026-11-19 on,
because labels apply forward.

## 3. Where the numbers come from

There is no billing export in the project (no billing dataset among its 77
datasets) and the billing API is closed to us. The source is therefore the
fallback the step allows: **`region-europe-west1.INFORMATION_SCHEMA.JOBS`**,
filtered to query jobs that read or wrote a `g07_*` dataset, plus `__TABLES__`
for table sizes and the GCS object listing. Two limits: days on which nothing
ran have no row at all, and this measures units, not invoiced money.

The project's whole query volume since 2026-11-01 is 115 GiB (11,943 jobs).
That is well inside the 1 TiB monthly free tier, so our **estimated** invoiced
amount is 0.00. **Not verified:**
- The free tier belongs to the billing account, not the project, and other
  projects on the same account may already have used it.
- We cannot read the billing account or its export (section 3,
  [billing-access.json](evidence/step9/billing-access.json)).

The dollars below are the units priced at list: what they would cost with no
free tier left.

The query, runnable as is:

```sql
SELECT DATE(creation_time) AS day, COUNT(*) AS jobs,
       SUM(total_bytes_billed) / POW(1024, 3) AS gib_billed
FROM `region-europe-west1`.INFORMATION_SCHEMA.JOBS
WHERE creation_time >= TIMESTAMP('2026-11-01') AND job_type = 'QUERY'
  AND (EXISTS (SELECT 1 FROM UNNEST(referenced_tables) t WHERE t.dataset_id LIKE 'g07_%')
       OR destination_table.dataset_id LIKE 'g07_%')
GROUP BY day ORDER BY day;
-- From 2026-11-19 on, the same question by label instead of by inference:
--   WHERE EXISTS (SELECT 1 FROM UNNEST(labels) l WHERE l.key = 'group' AND l.value = 'g07')
```

## 4. Largest cost: its SKU and its shape

| Line (SKU) | Measured units, 1-19 Nov | List price | At list |
|---|---|---|---|
| **BigQuery Analysis, on-demand (europe-west1)** | **25.09 GiB billed** | $7.50/TiB | **$0.184** |
| Cloud Storage Standard (europe-west1), Bronze bucket | 0.224 GiB stored, 2,685 objects | $0.02/GiB-month | $0.0045/month |
| BigQuery active logical storage | 0.080 GiB (warehouse 43.3 MB, gold 42.8 MB) | $0.02/GiB-month | $0.0016/month |
| Cloud Storage Class A (object writes) | 2,685 writes, 2,436 of them in `bronze/cdc/` | $0.005/1,000 | $0.013 once |

**The largest cost is BigQuery Analysis**, about 40 times the storage of
everything we keep. Its daily shape, in GiB billed
([evidence](evidence/step9/bigquery-daily-bytes.json)):

| 11-05 | 11-06 | 11-12 | 11-16 | 11-17 |
|---:|---:|---:|---:|---:|
| 0.21 | 6.64 | 0.94 | **12.41** | 4.90 |

**Shape 1, the runaway: one day, one SKU.** 2026-11-16 alone is **49%** of the
month. It was not one bad query. It was the Step 7 fire drill and back-fill:
about fourteen `dbt build` runs in an afternoon, at roughly 970 MiB each. 11-06
is the Step 4 tuning experiments. This is the only shape a budget alert would
ever catch, and only at list price, since it is free here.

**The line that matters next is shape 4, the thing nobody turned off.** Once the
DAG runs every day, every run costs the same whether or not anyone reads gold:
**1,215 MiB billed per scheduled `dbt build`** (104 jobs). That is about
**35.6 GiB a month, $0.26/month at list**, flat and forever. It never crosses a
threshold in a hurry, so no budget catches it. It is what section 5 reduces.

Underneath both: **billed is 3.3 times processed** (1,215 MiB billed for
364 MiB read). BigQuery bills at least 10 MB for each table a query references,
and most dbt tests read a few MB from one or two tables. That overhead, not
data volume, is most of our bill. It is BigQuery's version of shape 3
(small-file overhead). The GCS version is here too: `bronze/cdc/` holds 2,436
objects averaging 67 KB, and writing them cost $0.012, nearly three months of
storing the whole bucket.

## 5. One optimisation, with a before and an after

**The change: stop re-testing data that cannot change.** Ten silver models read
only the Step 2 snapshot (load `20261026T105159Z-2efcb86a`), which is frozen:
loaded once, never reloaded. Their 36 tests returned the same answer on every
run. They are now tagged `frozen_snapshot`, and the DAG runs
`dbt build --selector daily` six days a week and `--selector full` on Mondays
([`selectors.yml`](../transform/selectors.yml),
[DAG](../orchestration/dags/marketplace_daily.py)).

Every test that touches data which changes still runs every day: gold, the
scheduled extract, and `assert_reconciled_lines_preserved`, which reads both
the snapshot and the scheduled orders (`indirect_selection: cautious` keeps
it). Selection: 103 nodes in `full`, 57 in `daily`
([full](evidence/step9/selection-full.txt), [daily](evidence/step9/selection-daily.txt)).

| | Measured | Bytes billed per daily build | Jobs | At $7.50/TiB |
|---|---|---:|---:|---:|
| **Before** | 2026-11-17, last scheduled build ([evidence](evidence/step9/dbt-build-2026-11-17.json)) | **1,215 MiB** | 104 | $0.0087 per run |
| **After, predicted** | the same build minus the 46 jobs `daily` skips | 772 MiB | 58 | $0.0055 per run |
| **After, measured** | 2026-11-19 22:56 UTC, `dbt build --selector daily` ([evidence](evidence/step9/dbt-build-after-2026-11-19.json)) | **772 MiB** | **58** | **$0.0055 per run** |

The prediction removed from the 11-17 build exactly the jobs the selector
skips (443 MiB billed, 166 MiB processed). The measured run matched it to the
MiB: **772 MiB billed and 198 MiB processed, -36.5% per daily run**, with
`PASS=56 WARN=1 ERROR=0` (the warning is the 6 known unnamed products, by
design). Gold came out identical: same row count in all five tables. Every one
of the 58 jobs carried `group=g07`. With the
Monday full build, a month goes from 35.6 GiB to 24.5 GiB: **11.1 GiB a month
saved, about $0.08/month at list**. The estimated invoice saving is 0.00, if
the account's free tier is not already used up (not verifiable, section 3). The unit saving is the fact; the dollars are that fact, priced.

**What would tell us we were wrong:**

- **The after run billing much more than 772 MiB.** That would have meant the
  skipped jobs were not where the bytes were. It did not: 772.0 MiB, measured.
  From now on the same check runs on the label: the daily builds' bytes by
  `resource`, compared with this run.
- **A Monday `full` build fails a `frozen_snapshot` test that passed the Monday
  before.** That would prove the snapshot is not frozen (someone re-pointed a
  `g07_bronze` external table at a new load), and that up to six days of gold
  were built on unchecked data. The answer is then to remove the tag, not to
  keep the saving.
- **Not a signal either way:** money staying at 0.00. Inside the free tier,
  money cannot move.

**What the run found that we did not expect: the labels were wrong.** The
first build on the new config left the five gold tables with only
`layer=gold`. dbt *replaces* `+labels` set at project level with the ones set
on a folder, rather than merging them, so the run removed `group=g07` from
tables that had it. Found by reading the labels back after the run; fixed by
repeating all four keys on each folder in `dbt_project.yml` and rebuilding the
models only (21 jobs, 112 MiB, 22:58 UTC). All 15 silver views and 5 gold
tables now carry the four keys. Lesson for the convention: check labels on the
resource after the first run, not in the config.

**What the saving costs:** a change to the frozen data is caught within seven
days, not one. Any change to `transform/` still runs a full `dbt build` before
merge. The DAG change needs a transform image built from Step 9 or later,
because `selectors.yml` must be inside it.

## 6. The ledger

One row per resource group 7 owns, at list price, monthly unless stated. Units
measured 2026-11-19. Prices read 2026-11-19, except Cloud Storage operations
(2026-10-26, Step 2).

| Resource | What drives its cost | Measured units | Unit price (date read) | Estimate |
|---|---|---|---|---|
| `gs://data-engineering-i1-marketplace-group` (Bronze) | GiB stored; one Class A operation per object written | 0.224 GiB, 2,685 objects | Standard $0.02/GiB-month (2026-11-19); Class A $0.005/1,000 (2026-10-26) | $0.0045/month, plus writes |
| ... its lifecycle (Nearline at 30 days) | One operation per object moved, then Nearline rates and minimum durations | 20 objects move on 2026-11-25, 2,646 on 2026-12-05 | Nearline $0.01/GiB-month (2026-11-19); transition-operation rate not looked up | Storage halves; operations not estimated |
| `g07_bronze` | Nothing stored (external tables); the bytes scanned by jobs that read it | 0 bytes stored | - | $0 storage |
| `g07_warehouse` | Active logical GiB stored | 43.3 MB | $0.02/GiB-month (2026-11-19) | $0.0008/month |
| `g07_silver` | Nothing stored (views) | 0 bytes | - | $0 storage |
| `g07_gold` | Active logical GiB stored | 42.8 MB | $0.02/GiB-month (2026-11-19) | $0.0008/month |
| BigQuery queries, all `g07_*` jobs | GiB billed, 10 MB minimum per table referenced | 1,215 MiB per scheduled build before; 772 MiB after (measured 2026-11-19) | $7.50/TiB, first TiB free (2026-11-19) | $0.26/month before, $0.18 after |
| `gs://data-engineering-i1-g07-tfstate` (outside Terraform) | GiB stored, including noncurrent versions | 37.6 KB live object | $0.02/GiB-month (2026-11-19) | ~$0 |
| 12 dataset IAM bindings | Nothing | - | free | $0 |
| `g07-pipeline` service account and its 2 bucket and 4 dataset bindings (not created) | Nothing | - | free | $0 |
| Budget and its email channel (not created) | Nothing | - | free | $0 |
| **Total** | | | | **~$0.27/month at list; estimated 0.00 within the free tier, not verified** |

Outside GCP and outside this ledger: Airflow and the source system run on a
laptop (Docker Desktop), and the Docker Hub repositories under `omara11/` are
on a free personal plan (ADR 0006).

Until Step 9 this list could not be checked for completeness, because nothing
marked a resource as ours. With `group=g07` on every resource and job, a query
by label returns the whole list. Anything it misses is either outside
Terraform (named above) or a hand-made resource to adopt or delete.

How spend is attributed, and what would change with more teams:
[ADR 0009](adr/0009-cost-attribution.md).
