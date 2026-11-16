# Runbook: a `marketplace_daily` run failed

For the person on call who did not build this. Read it top to bottom; each section answers
one question, in the order you will need it.

Airflow runs on the operator's machine (Docker Desktop):

```powershell
docker compose -f orchestration/compose.yaml ps
```

UI: http://localhost:8080 (user `airflow`, password `airflow`; local only).

## 1. How do I know something is wrong?

A task that has failed **for the last time** (after its two retries, 5 minutes apart)
writes one line to **`orchestration/logs/alerts/failures.log`**, and posts it to the
webhook in `G07_ALERT_WEBHOOK` if one is set. Retries alone write nothing. A real line from
2026-11-16:

```text
{"at": "2026-11-16T15:41:45+00:00", "dag": "marketplace_daily", "task": "create_bronze_table", "period": "2026-09-15", "try": 3, "message": "[g07 pipeline FAILED] dag=marketplace_daily task=create_bronze_table period=2026-09-15 try=3 log=http://localhost:8080/dags/marketplace_daily/runs/backfill__2026-09-16T00%3A00%3A00%2B00%3A00/tasks/create_bronze_table?try_number=3"}
```

It names the task, the period it covered, the attempt, and a link to that attempt's log.
To watch the file:

```powershell
Get-Content orchestration\logs\alerts\failures.log -Wait
```

The run also shows red in the UI. **Silence is not proof of health:** a run that never
starts (see section 3b) writes nothing.

## 2. What do I look at first?

1. **The link in the alert line.** It opens the failed attempt's log. Otherwise: UI, DAG
   `marketplace_daily`, the red run, the red task, **Logs**.
2. **The last error line in that log.**
   - dbt prints `Database Error`, `FAIL` with a test name, or `Compilation Error`.
   - The extractor prints `Interval extraction stopped (<ErrorType>)`. It never prints
     connection details.
3. **Which task failed tells you where to look:**

| Failed task | Usually means | Look at |
|---|---|---|
| `extract_orders` | the source database is down or unreachable, or Google credentials are refused | `docker compose ps` (the `db` service), then credentials (section 3c) |
| `create_bronze_table` | BigQuery refused the table definition, or no Bronze file exists yet | the `Database Error` text |
| `dbt_build` or `dbt_test` | **a data test failed** (the quality gate), or BigQuery refused a model | the `FAIL <test name>` lines |

## 3. The three things that broke this week

**a. A bug inside an image.** On 2026-11-16, `create_bronze_table` failed 3 times with
`Database Error: Unknown option: labels`. The macro baked into the transform image used an
option BigQuery does not accept. Retrying cannot help, because every retry runs the same
image. The fix:
1. Fix the code and commit it.
2. Build a new image tagged `YYYY-MM-DD-<sha>` and push it (`docs/adr/0006-image-tags.md`).
3. Change the tag in `orchestration/dags/marketplace_daily.py`, the one place each image is
   named.
4. Clear the failed run (section 4).

**b. Runs stay "queued" and nothing happens.** The DAG is **paused**: Airflow 3 starts no
runs of a paused DAG, back-fills included, and sends no alert, because nothing failed.
Check with `airflow dags details marketplace_daily` (the `is_paused` line), and fix with:

```powershell
docker compose -f orchestration/compose.yaml exec airflow-scheduler airflow dags unpause marketplace_daily
```

**c. Credentials or the machine.** All of these happened this week:
- **Expired Google login.** gcloud said `Reauthentication failed`. Run
  `gcloud auth application-default login`, then copy the file into the volume the tasks
  read, `g07_gcloud` (`docs/orchestration.md`, "Set-up").
- **Docker Desktop crashed** with `Inference manager … dockerInference`. Restart Docker
  Desktop. **Never click "Reset to factory defaults"**: it deletes every volume, including
  the source database.
- **The source database container was stopped** after a reboot. Start it with
  `docker compose up -d migrate`.

## 4. Is it safe to just re-run it?

**Yes, for every task, with one exception.** Each writing task has a named mechanism
(`docs/adr/0007-idempotency.md`):

| Task | Why a rerun is safe |
|---|---|
| `extract_orders` | It writes a new Bronze load and never overwrites; silver keeps the newest load per day. A rerun adds a copy in Bronze and changes nothing in silver. |
| `create_bronze_table` | `CREATE OR REPLACE` of a table definition. |
| dbt | `CREATE OR REPLACE` of views and tables; tests only read. |

To re-run a period, clear it (failed tasks and everything downstream re-run):

```powershell
docker compose -f orchestration/compose.yaml exec airflow-scheduler airflow tasks clear marketplace_daily --start-date 2026-09-15 --end-date 2026-09-15 --yes
```

Or in the UI: the run, **Clear**, "include downstream".

**The exception: the quality gate.** If the failure is a dbt **test** (`FAIL unique_…`,
`FAIL not_null_…`), the data is wrong, and a rerun will fail the same way.
1. Find the bad rows. The test's compiled SQL, in the log, returns exactly those rows.
2. Fix the source, or remove the bad object from Bronze.
3. Only then clear the run.

**Never delete or disable the test to make the run green.** In `dbt build` mode the marts
were **not** rebuilt from the bad data (it stops at the first failing model and skips
everything after it), so gold still holds the last good numbers while you investigate.

Do not clear a period while the same period is still running.

## 5. Who do I tell, and when do I stop?

- **Tell:** Omar (owner of the alert) and the group channel, with the alert line and the
  last error line.
- **Stop and escalate, without retrying further, when:**
  - one manual rerun fails the same way;
  - the failure is a quality-gate test (section 4);
  - credentials are refused after a fresh login;
  - Bronze objects look missing or changed (Bronze is append-only, so nothing should ever
    disappear).
- **Never, while on call:**
  - `docker compose down -v` (it deletes volumes);
  - "Reset to factory defaults" in Docker Desktop;
  - deleting objects under `bronze/` other than a poison file you put there yourself;
  - removing a test.
