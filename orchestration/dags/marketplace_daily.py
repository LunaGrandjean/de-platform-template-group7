"""marketplace_daily: the group 7 pipeline, end to end, once a day (Step 7).

extract_orders  ->  create_bronze_table  ->  dbt (the quality gate)

Every task is a DockerOperator running one of the Step 6 images beside Airflow. This file
holds structure only: no pandas, no database query, nothing that does work at import time,
because the DAG processor re-parses it on a timer.

The period each task covers comes from the run ({{ data_interval_start | ds }}), never from
the clock, so a back-fill of last month extracts last month. How each task stays safe to
run twice is in docs/orchestration.md and docs/adr/0007-idempotency.md.
"""

from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timedelta, timezone

import pendulum
from airflow.providers.docker.operators.docker import DockerOperator
from airflow.sdk import DAG
from airflow.timetables.interval import CronDataIntervalTimetable
from docker.types import Mount

# One place per image: rolling back is changing this tag (ADR 0006). Never "latest".
INGESTION_IMAGE = os.environ.get("G07_INGESTION_IMAGE") or "omara11/group7-ingestion:2026-11-12-90355ad"
TRANSFORM_IMAGE = os.environ.get("G07_TRANSFORM_IMAGE") or "omara11/group7-transform:2026-11-12-90355ad"

# "lock": dbt build tests each model as it is built and skips everything downstream of a
# failure, so bad data stops before the marts. "alarm": dbt run, then dbt test, so the
# marts are rebuilt first and the test only reports afterwards. Lock is the fix; alarm is
# kept so the fire drill can show both states (docs/orchestration.md).
GATE = os.environ.get("G07_GATE", "lock")

SOURCE_NETWORK = "albert-marketplace_default"   # the source system's compose network
CREDENTIALS = Mount(source="g07_gcloud", target="/gcp", type="volume", read_only=True)
GOOGLE_ENV = {
    "GOOGLE_APPLICATION_CREDENTIALS": "/gcp/application_default_credentials.json",
    "GOOGLE_CLOUD_PROJECT": "data-engineering-i1",
    "GCP_PROJECT_ID": "data-engineering-i1",
}
ALERT_LOG = "/opt/airflow/logs/alerts/failures.log"
LOGGER = logging.getLogger(__name__)


def notify_failure(context) -> None:
    """Runs once a task has failed for the last time (on_failure_callback), not on every retry.

    Writes one line to the alert log, and posts it to G07_ALERT_WEBHOOK when one is set
    (Slack and Discord both accept this payload). It never raises: a broken alert must not
    hide the original failure.
    """
    ti = context["task_instance"]
    message = (f"[g07 pipeline FAILED] dag={ti.dag_id} task={ti.task_id} "
               f"period={context['data_interval_start']:%Y-%m-%d} try={ti.try_number} "
               f"log={getattr(ti, 'log_url', 'see the Airflow UI')}")
    record = {"at": datetime.now(timezone.utc).isoformat(), "dag": ti.dag_id, "task": ti.task_id,
              "period": f"{context['data_interval_start']:%Y-%m-%d}", "try": ti.try_number,
              "message": message}
    LOGGER.error(message)
    try:
        os.makedirs(os.path.dirname(ALERT_LOG), exist_ok=True)
        with open(ALERT_LOG, "a", encoding="utf-8") as output:
            output.write(json.dumps(record) + "\n")
    except OSError:
        LOGGER.exception("Could not write the alert log")
    webhook = os.environ.get("G07_ALERT_WEBHOOK")
    if webhook:
        import urllib.request  # only when an alert is actually sent

        request = urllib.request.Request(webhook, data=json.dumps({"text": message, "content": message}).encode(),
                                         headers={"Content-Type": "application/json"}, method="POST")
        try:
            urllib.request.urlopen(request, timeout=10)
        except Exception:
            LOGGER.exception("Could not post the alert to the webhook")


def container(task_id: str, image: str, command: list[str], environment: dict,
              network: str | None = None) -> DockerOperator:
    return DockerOperator(
        task_id=task_id,
        image=image,
        command=command,
        environment=environment,
        mounts=[CREDENTIALS],
        network_mode=network,
        docker_url="unix://var/run/docker.sock",
        mount_tmp_dir=False,
        auto_remove="success",
        force_pull=False,          # pull only when the tag is missing locally (Docker Hub limits)
    )


with DAG(
    dag_id="marketplace_daily",
    description="Orders from the source into Bronze, then dbt builds and tests silver and gold.",
    # Explicitly an interval timetable. In Airflow 3 a plain "@daily" makes runs with no
    # data interval (start == end), which would give the extractor an empty period; this
    # gives each run the day before it: [00:00, next 00:00).
    schedule=CronDataIntervalTimetable("0 0 * * *", timezone="UTC"),
    start_date=pendulum.datetime(2026, 9, 15, tz="UTC"),
    catchup=False,
    max_active_runs=1,
    default_args={
        "owner": "group7",
        "retries": 2,
        # Longer than anything we retry: a dropped connection or a BigQuery hiccup
        # clears in minutes, and three quick failures would only page somebody sooner.
        "retry_delay": timedelta(minutes=5),
        "execution_timeout": timedelta(minutes=30),
        "on_failure_callback": notify_failure,
    },
    tags=["group7", "step7"],
) as dag:
    extract_orders = container(
        "extract_orders", INGESTION_IMAGE,
        ["python", "ingestion/extract_orders.py"],
        {
            **GOOGLE_ENV,
            "BRONZE_BUCKET": "data-engineering-i1-marketplace-group",
            "PGHOST": "db", "PGPORT": "5432", "PGDATABASE": "marketplace", "PGUSER": "postgres",
            "PGPASSWORD": os.environ.get("G07_SOURCE_PASSWORD", "postgres"),
            "SOURCE_ID": "g07-airflow",
            # The period, from the run. The extractor reads these when no flags are given.
            "INTERVAL_START": "{{ data_interval_start | ds }}",
            "INTERVAL_END": "{{ data_interval_end | ds }}",
        },
        network=SOURCE_NETWORK,
    )

    create_bronze_table = container(
        "create_bronze_table", TRANSFORM_IMAGE,
        ["run-operation", "create_scheduled_orders_table"], GOOGLE_ENV,
    )

    if GATE == "alarm":
        dbt_run = container("dbt_run", TRANSFORM_IMAGE, ["run"], GOOGLE_ENV)
        dbt_test = container("dbt_test", TRANSFORM_IMAGE, ["test"], GOOGLE_ENV)
        extract_orders >> create_bronze_table >> dbt_run >> dbt_test
    else:
        dbt_build = container("dbt_build", TRANSFORM_IMAGE, ["build"], GOOGLE_ENV)
        extract_orders >> create_bronze_table >> dbt_build
