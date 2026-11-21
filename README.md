# Albert's Marketplace data platform

This is our group's data platform for Albert's Marketplace, a fictional European
beauty-products marketplace used in the Data Engineering & Cloud Infrastructure
course at Albert School. Steps 1 and 2 document the platform design and establish
the raw Bronze layer in Google Cloud Storage.

The repository also includes the provided marketplace source system: its
operational PostgreSQL database, storefront and generators for historical data
and live traffic. Those components support the later ingestion exercises. The
course template supplies the group-repository structure and collaboration files.

**Everything in it is made up.** Every customer, address, phone number,
password and payment card is synthetic. Product and review text comes from a
public research dataset, and images are URLs into someone else's host, never
copies. See [`docs/dataset-card.md`](docs/dataset-card.md).

## Student data platform

The course platform documentation is developed on branch `Luna`. The source
system below provides its PostgreSQL data, released CSV extracts and Kafka
events. The platform targets daily units sold by product and country.

### Team

| Member | GitHub handle | Contribution |
|---|---|---|
| Luna Grandjean | [@LunaGrandjean](https://github.com/LunaGrandjean) | Initial platform design and documentation |
| Omar Abdellatif | [@abdellatifomar61-ship-it](https://github.com/abdellatifomar61-ship-it) | Step 6 container images (Dockerfiles, Docker Hub tags, reproduction, retention, ADR 0006) and Step 7 Airflow orchestration (DAG, alerts, fire drill, back-fill, runbook, ADR 0007) |
| Malek Saoudi | [@Msaoudi115](https://github.com/Msaoudi115) | Step 3 live Docker/Debezium deployment and evidence |
| Anas Mossad | [@realay04](https://github.com/realay04) | Step 9 FinOps: label convention (Terraform, dbt jobs), budget, largest-cost analysis, the frozen-snapshot test optimisation, the ledger and ADR 0009 |
| Emile Gadenne | [@egadenne-ai](https://github.com/egadenne-ai) | Step 4 BigQuery warehouse, costed queries and ADR 0004; Step 8 Terraform (adoption by import, remote state, drift, pipeline identity, ADR 0008) |

We are group 7 (`g07`). The cohort identifier has not been provided yet. Add it
before submitting the group repository.

### Step 1: Start the Platform

| Deliverable | Content |
|---|---|
| [Data flows](docs/data-flows.md) | Sources, consumers, frequencies, formats and three risk questions |
| [Target architecture ADR](docs/adr/0001-target-architecture.md) | Comparison of warehouse, lake, two-tier and lakehouse architectures |
| [Architecture](docs/architecture.md) | Context diagram, current status and Bronze/Silver/Gold guarantees |
| [Daily-demand star](docs/model/star-daily-demand.md) | Business process, grain, dimensions and measures |

The Step 1 architecture is a design; subsequent deployment status is tracked
in the architecture document and the step checklists below.

Step 1 completion checklist:

- [x] Document the source flows and their risks.
- [x] Compare four architecture options and record the target decision.
- [x] Add an architecture diagram and layer contracts.
- [x] Sketch the daily-demand star schema.
- [x] Complete the team table with all members and GitHub handles.
- [ ] Add the cohort and group identifier.
- [ ] Verify a private group repository named `de-<cohort>-<group>` was created
  from `de-platform-template`. Verify its privacy, name and template origin;
  a personal branch alone does not meet this course requirement.
- [ ] Add every member and `Charlestng` as collaborators and verify that all
  invitations are accepted.
- [ ] Email the private repository URL and group names to
  `charlestanguypro@gmail.com`, with subject
  `MSA-DAT09-02 | L01-REPO | <cohort> | <group>`.
- [ ] Have every member push at least one commit.
- [ ] Merge at least one pull request after another member reviews it.

Keep the course repository and its access intact until marks are published.
Submit changes through reviewed pull requests. Commit history is part of the
assessment. Keep a separate commit for each project step.

### Step 2: The Bronze Layer

The shared bucket is `gs://data-engineering-i1-marketplace-group`, in project
`data-engineering-i1`, region `europe-west1`. The initial snapshot contains
seven tables, 1,296,708 raw rows and 19 Snappy Parquet files, partitioned by
ingestion date and unique load ID. No source columns or parsed values were
cleaned, deduplicated or dropped.

| Deliverable | Content |
|---|---|
| [Setup and verification](docs/bronze-setup.md) | Reproducible uv commands, actual load and remaining group checks |
| [Bronze layout ADR](docs/adr/0002-bronze-layout.md) | Partition/format/codec decisions and measured evidence |
| [Data dictionary](docs/data-dictionary.md) | All 39 source columns, source and physical types, personal-data flags |
| [Applied lifecycle](infra/lifecycle.json) | Live non-deleting storage-class transitions at 30, 90 and 365 days |
| [Actual IAM](infra/iam.md) | Verified bucket bindings and effective-access limitations |
| [Cost baseline](docs/costs.md) | Dated published prices, measured volumes and a 100x scenario |
| [Architecture](docs/architecture.md) | Actual bucket, region, layout and planned readers |

Cloud operations run through `uv` and the Python SDK using local Application
Default Credentials; no administrator installation or `gcloud` is required.
Generated CSV/Parquet data and credentials are excluded from Git. The committed
[evidence](docs/evidence/step2/) contains metadata, counts and checksums only.

Group-member Google access still needs individual verification.

### Step 3: Route 3 — Python ingestion (no Airbyte) — COMPLETE

**Step 3 is complete.** The orders cursor, clickstream consumer and Debezium
CDC path are implemented; live Bronze writes, CDC CRUD events and restart/resume
were verified. The point-in-time evidence is in
[`cdc-status.json`](docs/evidence/step3/cdc-status.json). For a fresh clone,
follow the [Step 3 reproduction guide](docs/runbooks/step3-reproduction.md).

The group selected Route 3 from the course setup: use a hand-written psycopg
extractor, Python Kafka consumers and Debezium Connect for CDC; Airbyte is not
part of this route.
`psycopg[binary]` is included in the locked project environment, installed with
`uv sync --locked`.

The operator-reported Route 3 run on 2026-11-05 first wrote 13 new orders in
one batch, advancing the cursor to 225168. The Bronze audit verified the
existing paths, then a one-shot catch-up wrote 237 rows through order ID
225405. The orders prefix now has 50 Parquet objects and 225,381 rows; the
current source had two more rows at the post-run check. There are also 129 main
clickstream objects (29,144 rows), two rows in the isolated Kafka test topic,
and one test DLQ object. The orders prefix includes a 225,000-row backfill from
ID 1, so it overlaps the Step 2 orders snapshot and must not be summed with it.
Details: [Bronze verification](docs/evidence/step3/bronze-verification.json)
and [Route 3 run evidence](docs/evidence/step3/route3-live-run.json).

| Deliverable | Content / status |
|---|---|
| [Ingestion guide](ingestion/README.md) | Locked dependencies, commands, checkpoints and delivery guarantees |
| [Orders extractor](ingestion/extract_orders.py) | Hand-written parameterised psycopg extraction with persistent cursor and bounded retries |
| [Kafka consumer](ingestion/consume_clickstream.py) and [schema v1](ingestion/clickstream.schema.json) | Parquet/DLQ implementation; main and isolated-test objects and Parquet footers verified in GCS |
| [Debezium CDC connector](ingestion/configure_cdc.py) and [Bronze consumer](ingestion/consume_cdc.py) | Existing PostgreSQL publication/slot into Kafka and append-only `bronze/cdc/` |
| [CDC runtime evidence](docs/evidence/step3/cdc-status.json) | Snapshot, seven-table output, slot/WAL, heartbeat, restart/resume and synthetic CRUD verification |
| [Route 3 evidence](docs/evidence/step3/route3-live-run.json) and [Bronze audit](docs/evidence/step3/bronze-verification.json) | Reported job run plus read-only GCS inventory, schemas, row counts and freshness check |
| [Failure modes](docs/ingestion-failure-modes.md) and [architecture](docs/architecture.md) | Cursor limitations, at-least-once delivery and layer contracts |

The orders cursor captures visible higher `order_id` values; it does not detect
updates, deletes or lower IDs that commit late. Debezium uses the existing
publication and slot for row-level CDC on seven tables; the Python CDC consumer
preserves raw envelopes and tombstones with Kafka provenance in `bronze/cdc/`.
See [CDC runtime evidence](docs/evidence/step3/cdc-status.json). Step 4 exposes the Python orders and main clickstream prefixes as external
tables; native sales tables still use the pinned Step 2 snapshot.

The evidence counts and object names describe the source and GCS bucket at
their recorded timestamps. A fresh clone creates new local state and later
objects, so it reproduces the pipeline and checks, not byte-identical counts.

### Step 4: SQL Warehouse

Bronze stays in the bucket and is read through seven BigQuery external tables
in `g07_bronze`. The two sales tables are copied, typed, into `g07_warehouse`,
partitioned by month and clustered by product. Measured with the cache off, a
month of daily demand reads 49x fewer bytes natively than from Bronze, and
filters that cannot prune are rejected before they run. The native tables cover
the Step 2 snapshot; the Python and main clickstream paths are separate
external tables. Malek's Debezium implementation and live evidence are included.
Review fixes add the MV SQL, corrected costs, fail-closed prechecks, pricing
comparison and incident runbook. See [live validation status](docs/evidence/step4/validation-status.json)
for the successful 2026-11-06 cloud checks: the daily-demand MV, controlled
clustering comparisons and deliberate maximum-bytes cap failure are verified.

| Deliverable | Content |
|---|---|
| [Tuning and cap verification](docs/warehouse-tuning.md) | Processed-byte comparisons, aggregation ratios and reproducible live checks |
| [Daily-demand MV](warehouse/daily-demand.sql) | Deployed product/day aggregation; independently verified results and collapse ratio |
| [Pricing decision](docs/adr/0004-warehouse-pricing.md) | Workload assumptions, capacity break-even and review thresholds |
| [Slow-query runbook](docs/runbooks/slow-query.md) | Ordered investigation, evidence and escalation |
| [Warehouse and costed queries](docs/warehouse.md) | Datasets, tables, reproduction commands and three queries measured in bytes and dollars |
| [Warehouse ADR](docs/adr/0004-warehouse-tables.md) | External versus native tables, partition grain, clustering and the empty-column workaround |
| [Warehouse script](scripts/warehouse.py) | `external`, `native` and `measure` commands, with row-count and cast prechecks |
| [Evidence](docs/evidence/step4/) | External and native table metadata, job IDs and query measurements |
| [Dictionary](docs/data-dictionary.md) and [architecture](docs/architecture.md) | Warehouse schemas and updated status |

### Step 6: Container images

Both jobs now run from images that carry their own interpreter, dependencies and code:
the Step 3 ingestion jobs and the Step 5 dbt project. Each image is pinned at both
ends (the base image to a patch version, the dependencies by lock file), runs as a
non-root user, and contains no credentials.

| Deliverable | Content |
|---|---|
| [`ingestion/Dockerfile`](ingestion/Dockerfile) | Step 3 extractors on `python:3.12.12-slim-bookworm`, `uv.lock` installed with `--locked`. Nothing runs by default. |
| [`transform/Dockerfile`](transform/Dockerfile) | Step 5 dbt project: `dbt-core` 1.12.6 and `dbt-bigquery` 1.12.2 from `uv.lock`, `dbt_utils` 1.4.1 from `package-lock.yml`. `dbt` is the entrypoint. |
| [`.dockerignore`](.dockerignore) | Allow-list for both builds. `.env`, virtualenvs, `.git` and credential files never enter a build. |
| [Tag and registry ADR](docs/adr/0006-image-tags.md) | Tag `YYYY-MM-DD-<git sha>`, never `latest`; registry; rollback commands; retention policy, executed on 2026-11-16. |
| [Reproduction](docs/reproduce.md) | Run, delete, pull, run again, and compare the two digests. Run on 2026-11-12: the digests match. The retention deletion was run on 2026-11-16. |

Images are named `group7-ingestion` and `group7-transform` and are hosted on Docker Hub
under `omara11/`, in public repositories, so pulling needs no login. They hold
no secret and no data. Both were pushed on 2026-11-12 as tag `2026-11-12-90355ad`, the commit they were built
from; their digests are recorded in `docs/reproduce.md`.

#### Install and run the images

You need Docker Desktop running and about 3 GB of free disk. Steps 1 and 2 need
nothing else. Run everything from the repository root.

1. **Build both images.** The final `.` is the build context, and the root
   `.dockerignore` applies to it. Use a non-`latest` tag; for a build you mean to keep,
   use `YYYY-MM-DD-<short sha>`.

   ```
   docker build -f ingestion/Dockerfile --build-arg GIT_SHA=<short sha> -t omara11/group7-ingestion:<tag> .
   docker build -f transform/Dockerfile --build-arg GIT_SHA=<short sha> -t omara11/group7-transform:<tag> .
   ```

2. **Run the ingestion job against the local source, writing to a local volume.** No
   Google account is needed. Start the source database with `migrate`: on a fresh
   machine it first downloads the released dataset (66 MB) and restores it, which takes
   about a minute. Starting `db` on its own would give you an empty database, and the job
   would fail with `UndefinedTable`. `migrate` does not start the load generator, so the
   row count stays fixed. (If you started everything with `docker compose up`, run
   `docker compose stop load-generator` first.)

   ```
   docker compose up -d migrate
   docker run --rm --network albert-marketplace_default -e PGHOST=db -e PGDATABASE=marketplace -e PGUSER=postgres -e PGPASSWORD=postgres -e SOURCE_ID=g07-local-check -v g07_state:/state omara11/group7-ingestion:<tag> python ingestion/extract_orders.py --once --local-output /state/bronze --state-file /state/orders-local.json
   ```

   On a freshly seeded database it prints
   `{"rows": 222644, "batches": 45, "last_order_id": 222644}`; if the load generator has
   run, the numbers are higher. Run it again and it prints `"rows": 0`,
   because the cursor in the `g07_state` volume is already at the end. `docker volume rm
   g07_state` starts it over.

3. **Run dbt.** This needs your own Google credentials (the Application Default
   Credentials file from Step 2), mounted read-only. In PowerShell:

   ```
   $adc = "$env:APPDATA\gcloud\application_default_credentials.json"
   docker run --rm -v "${adc}:/gcp/adc.json:ro" -e GOOGLE_APPLICATION_CREDENTIALS=/gcp/adc.json -e GOOGLE_CLOUD_PROJECT=data-engineering-i1 omara11/group7-transform:<tag> parse
   ```

   On macOS or Linux the file is `$HOME/.config/gcloud/application_default_credentials.json`.
   Replace `parse` with `source freshness` or `build` to run those. **`build` replaces the
   silver and gold objects in the shared project.**

To pull a pushed image instead of building it, Docker alone is enough. The tag pushed
so far is `2026-11-12-90355ad`:

```
docker pull omara11/group7-ingestion:<tag>
docker pull omara11/group7-transform:<tag>
```

Things that look wrong and are not:

- A bare `docker run <image>` only prints help. Neither image has a default that writes
  anything; the job is always chosen on the command line.
- The extractor's cursor is a file in `/state`. Without a named volume there, every run
  starts again from order 0.
- `docker run ... omara11/group7-transform:<tag> debug` ends with one failed check, `git`. The
  slim image has no `git`, which only git-based dbt packages need; ours come from
  `package-lock.yml`. The line that matters is `Connection test: OK`.

### Step 7: The pipeline on a schedule

Airflow runs the pipeline every day without a person: the orders for the day, then the
external table, then `dbt build`, which stops before the marts when a test fails.

| Deliverable | Content |
|---|---|
| [DAG](orchestration/dags/marketplace_daily.py) and [compose file](orchestration/compose.yaml) | `marketplace_daily`, three `DockerOperator` tasks on the Step 6 images; Airflow 3.3.2, lean enough for an 8 GB laptop |
| [Orchestration](docs/orchestration.md) | Set-up, the idempotency note per task, retries and the alert, the fire drill (alarm, then lock), the back-fill with its prediction |
| [Runbook](docs/runbooks/failed-run.md) | For the person on call: what to look at, what broke this week, and whether a rerun is safe |
| [ADR 0007](docs/adr/0007-idempotency.md) | How reruns are made safe, the alternative per task, the one we are least sure about |

The extractor gained an interval mode for this step
([`ingestion/extract_orders.py`](ingestion/extract_orders.py)): it reads the orders of the
run's period and writes a new, never-overwritten Bronze load per day.

### Step 8: Infrastructure as code

The Bronze bucket, the four `g07_*` datasets and their named grants are declared in
Terraform and changed only through it. They already existed, so they were adopted with
import blocks, not recreated; the first plan after adoption said "No changes".

| Deliverable | Content |
|---|---|
| [`infra/terraform/`](infra/terraform/) | Terraform 1.17.1, Google provider 8.9.0 pinned with its lock file; 17 adopted resources, `prevent_destroy` on the bucket and datasets |
| [Infrastructure](docs/infra.md) | How to run it, one line per resource and why it exists, what stays outside Terraform (tables, Docker Hub images), the drift exercise, and the identity the Step 7 pipeline should run as |
| [ADR 0008](docs/adr/0008-remote-state.md) | State in a versioned GCS bucket of our own, and what to do if it is deleted |
| [Evidence](docs/evidence/step8/) | Transcripts of the adoption, the provoked drift and the final plans |
| [CI check](.github/workflows/terraform.yml) | `fmt -check`, `init -backend=false` and `validate` on every PR touching `infra/terraform/`, with no cloud credential |

The pipeline service account is declared with exactly the grants the three DAG tasks need,
but not created: our accounts cannot create service accounts in the shared project. Until
the course admin creates it, Airflow runs as a person through the project's default
bindings ([infra.md](docs/infra.md#the-pipelines-identity-steps-7-and-8)).

### Step 9: Attributable, and one saving measured

Every resource and every BigQuery job our code runs now carries four labels (`group`,
`env`, `layer`, `component`), so what the pipeline costs is a query, not a guess. Spend
before 2026-11-19 carries no label and stays unattributable. Our largest cost is BigQuery
Analysis (25.1 GiB billed in November; an estimated 0.00 within the free tier, unverified
because we cannot read the billing account). One daily
`dbt build` billed 1,215 MiB; skipping the tests of the frozen Step 2 snapshot on six days
out of seven brought it to 772 MiB (-36.5%), measured on 2026-11-19 with gold unchanged.

| Deliverable | Content |
|---|---|
| [Label convention](docs/costs.md#1-label-convention) | Four keys and why each exists, applied by Terraform [`default_labels`](infra/terraform/labels.tf), dbt job labels ([macro](transform/macros/g07_query_comment.sql)) and `scripts/warehouse.py`; what is already unattributable |
| [Budget alert](infra/terraform/budget.tf) | Label-scoped budget, one named recipient, and what it does not stop. Declared, not created: the billing API is closed to us |
| [Largest cost](docs/costs.md#4-largest-cost-its-sku-and-its-shape) | BigQuery Analysis by SKU, its daily shape (shape 1 on 11-16, shape 4 going forward) and the 10 MB-per-table overhead |
| [One optimisation](docs/costs.md#5-one-optimisation-with-a-before-and-an-after) | [`selectors.yml`](transform/selectors.yml) and the [DAG](orchestration/dags/marketplace_daily.py): before, after, units and what would prove it wrong |
| [Ledger](docs/costs.md#6-the-ledger) | One row per resource, with the unit price and the date it was read |
| [ADR 0009](docs/adr/0009-cost-attribution.md) | Labels on resources and jobs over a project per team, tags or a manual split, and what changes at ten teams |
| [Evidence](docs/evidence/step9/) | Daily bytes, the 11-17 build job by job, storage inventory, prices, label check, selections and the label-only `terraform plan` |

**Delivery.** Commit `3bb044f` on `anas/step9-finops`, rebased on `main` after PR #6
(Step 8), reviewed in [PR #9](https://github.com/LunaGrandjean/de-platform-template-group7/pull/9).
Checked before opening: `tests/test_warehouse.py` 12 passed, `dbt ls` 103 nodes in
`full` and 57 in `daily`, `terraform validate` OK. Still open, and why each one blocks:

| Open item | Owner | Blocks |
|---|---|---|
| Transform image with `selectors.yml`, and `TRANSFORM_IMAGE` bumped in the DAG | Omar | Merging: the DAG passes `--selector`, and the current image `2026-11-17-e8df6e5` has no `selectors.yml` |
| `terraform apply` of the labels (plan: 0 add, 5 change, 0 destroy) | Emile | Labels on the bucket and datasets; needs Terraform 1.17 and the team's go-ahead |
| Billing account ID and project number | Course admin | Creating the budget (`count = 0` until then) |

## Start it

You need Docker Desktop (or Docker Engine with Compose v2), about 6 GB of free
disk and 3 GB of free RAM.

```
git clone https://github.com/TangoAI-AlbertSchool-Data-Eng-Cloud/albert-marketplace.git
cd albert-marketplace
docker compose up
```

The first start downloads the dataset (a 66 MB database dump, published as a
release asset) and restores it, which takes a minute or two. Later starts find
the data already there and skip it. Then:

| What | Where | |
|---|---|---|
| Storefront (the shop) | http://localhost:8510 | Streamlit |
| Storefront API | http://localhost:8100/docs | FastAPI, [endpoints](storefront/README.md) |
| PostgreSQL | `localhost:5432` | database `marketplace`, user `postgres`, password `postgres` |
| Kafka | `localhost:9092` | topic `clickstream` |

The load generator starts with everything else: it shops through the API on a
simulated clock, so orders, payments and shipments keep arriving in the
database, and clickstream events keep arriving on the Kafka topic.

Stop it with `Ctrl+C`, and `docker compose down` to remove the containers. The
data lives in a Docker volume and survives both; `docker compose down -v`
deletes it, and the next start downloads the dataset again.

## Connect to it

From your machine:

```
psql postgresql://postgres:postgres@localhost:5432/marketplace
```

From another container on your machine (Airbyte, Airflow, dbt), the database is
`host.docker.internal:5432` and Kafka is `host.docker.internal:29092`.

PostgreSQL runs with `wal_level=logical`, so change data capture works: create a
replication slot, or point Airbyte or Debezium at it. A slot can become invalid when retained WAL exceeds the 512 MB setting;
it is not automatically dropped. Monitor the group slot and coordinate any
resnapshot rather than dropping it during routine operation.

## What is in here

| | |
|---|---|
| [`db/`](db/) | The schema, as dbmate migrations, and `load_legacy.sql`, which loads the original CSV extract with its defects |
| [`storefront/`](storefront/) | FastAPI backend and Streamlit shop ([README](storefront/README.md)) |
| [`generators/`](generators/) | `history/` builds the order history; `live/traffic.py` is the load generator |
| [`tests/`](tests/) | The checks behind the build spec's verified claims |
| [`docs/`](docs/) | [Dataset card](docs/dataset-card.md), [build spec](docs/build-spec.md), and `critique/`: original files the course picks apart |
| `data/` | Downloads and generated files. Never in git |

The schema is the contract between all of it: 25 tables from the original
extract, plus `ORDER_ITEMS` (order lines) and `PAYMENT` (one transaction per
order).

## Settings

Every setting has a default, so `docker compose up` needs no `.env`. Override
any of them in the environment or in a `.env` file next to `compose.yaml`.

| Variable | Default | |
|---|---|---|
| `DB_PORT`, `API_PORT`, `UI_PORT` | 5432, 8100, 8510 | host ports, if one is taken |
| `KAFKA_PORT`, `KAFKA_DOCKER_PORT` | 9092, 29092 | from your machine, from another container |
| `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | postgres, postgres, marketplace | |
| `SEED_URL` | the release asset | set it empty to start on an empty database |
| `CLOCK_ACCELERATION` | 15 | how much faster than real time the live traffic runs |
| `ORDERS_PER_DAY` | 200 | orders per simulated day |
| `TRAFFIC_SEED` | 20260915 | the load generator's seed |
| `SIMULATION` | true | lets the load generator date orders on its own clock. Off, the storefront uses the real time |

To run without the live traffic:
`docker compose up db seed migrate storefront-api storefront-ui`.

## Rebuild the dataset

You do not need this to follow the course: the release asset is the dataset.
It is here because the course reads it.

The `build` profile holds the services that make the data. They need the
original CSV extract in `LEGACY_CSV_DIR` and, for the calibration, Online
Retail II in `RETAIL_XLSX_DIR`.

```
docker compose --profile build run --rm load-legacy        # CSVs -> database
docker compose --profile build run --rm calibrate          # -> history/calibration.json
docker compose --profile build run --rm fetch-places       # GeoNames -> history/places.json
docker compose --profile build run --rm generate-history --seed 7 --end-date 2026-09-15
docker compose --profile build run --rm release            # -> data/release/
```

`--scale` changes how many orders those three years hold, without touching the
customers or the catalogue: `--scale 0.1` for a tenth of them (a small copy for
a laptop or for CI), `--scale 5` for five times as many. Every rule the full
dataset follows still holds, duplicates included.

The history generator is deterministic: the same seed, end date and scale give
the same database every time. Tear these down with
`docker compose --profile build down`; a plain `down` leaves their containers
behind.

## Support tickets

120 messages to the company's support inbox, each labelled with the team that
should handle it, for the LLM course. They are a separate release,
[`tickets-v1.0.0`](https://github.com/TangoAI-AlbertSchool-Data-Eng-Cloud/albert-marketplace/releases/tag/tickets-v1.0.0):
download `tickets_v1.csv`. A language model wrote the wording from real rows of
the dataset; a person checked every label. How they were made, and how to
rebuild the first sixty without calling the model:
[docs/tickets-card.md](docs/tickets-card.md).

## Licence and attribution

The course template files and structure remain the course author's intellectual
property and are supplied for this course only. No licence is granted for those
template materials; the group's work belongs to the group, as stated in the
original template README. The source-system licences and attributions below
apply to the imported marketplace code and dataset.

- **Code: MIT** ([LICENSE](LICENSE)).
- **Data: CC BY-SA 4.0.** It is derived from:
  - McAuley Lab's Amazon Reviews'23: Hou, Y., Li, J., He, Z., Yan, A., Chen, X.,
    McAuley, J. (2024). *Bridging Language and Items for Retrieval and
    Recommendation.* arXiv:2403.03952
  - UCI Online Retail II, used for calibration only: Chen, D. (2012). *Online
    Retail II* [Dataset]. UCI Machine Learning Repository.
    https://doi.org/10.24432/C5CG6D. CC BY 4.0
  - GeoNames postal codes (https://www.geonames.org/), CC BY 4.0, for addresses
  - Eurostat population figures, for the country and region mix

The storefront and the original schema began as
[amazon-database-design](https://github.com/JedhaBootcamp/amazon-database-design)
and
[amazon-mockup-e-commerce](https://github.com/JedhaBootcamp/amazon-mockup-e-commerce).
