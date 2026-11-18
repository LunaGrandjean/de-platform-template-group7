# Orchestration

Airflow 3.3.2 runs the pipeline daily: the DAG
[`dags/marketplace_daily.py`](dags/marketplace_daily.py) starts the Step 6 images in
order (`extract_orders`, then `create_bronze_table`, then `dbt_build`), with retries, a
failure alert and `dbt build` as the quality gate.

- Start: `docker compose -f orchestration/compose.yaml up -d`, UI at http://localhost:8080
- How it works, set-up, idempotency, the fire drill and the back-fill:
  [docs/orchestration.md](../docs/orchestration.md)
- When a run fails: [docs/runbooks/failed-run.md](../docs/runbooks/failed-run.md)
- Why reruns are safe: [docs/adr/0007-idempotency.md](../docs/adr/0007-idempotency.md)

`dags/` is what Airflow reads. `logs/` (task logs and `alerts/failures.log`) and `.env`
(per-machine settings) are ignored by Git.
