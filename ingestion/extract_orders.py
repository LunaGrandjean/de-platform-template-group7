"""Extract public.orders from PostgreSQL to Bronze Parquet, using psycopg without an ORM.

Cursor mode (Step 3, the default): incremental INSERT-only extraction by order_id.
Single writer per state file. Each batch is written before its atomic cursor
checkpoint. A crash between those actions can duplicate the batch on restart;
Bronze does not deduplicate it. Updates, deletes, source resets and transactions
committing later with IDs below the watermark are NOT captured. This is not CDC
and is not the authoritative sales input. Use the separate connector stream.

Interval mode (Step 7, used by the scheduler): --interval-start/--interval-end, or
INTERVAL_START/INTERVAL_END, select the orders whose order_date falls in
[start, end), and their order lines. The period comes from the run, never from the
clock. Each day is written as two new objects under the same load id,
bronze/scheduled/order_items/interval_date=D/load_id=L/ first, then
bronze/scheduled/orders/interval_date=D/load_id=L/, and nothing is ever
overwritten: a rerun adds a newer load, and silver keeps only the newest orders
load per day and the lines of that same load (models/staging/stg_scheduled_*.sql).
Lines go first, so an orders load that exists always has its lines; a crash in
between leaves only a lines load that silver ignores.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import time
import uuid
from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import psycopg
import pyarrow as pa
from psycopg.rows import dict_row

if __package__:
    from .common import load_environment, make_store, parquet_named, parquet_object, utc_now
else:
    from common import load_environment, make_store, parquet_named, parquet_object, utc_now

LOGGER = logging.getLogger(__name__)
SCHEMA = pa.schema([
    ("order_id", pa.int64()), ("buyer_id", pa.string()),
    ("discount_id", pa.int64()), ("payment_id", pa.int64()), ("order_date", pa.date32()),
])


@contextmanager
def state_lock(path: Path):
    """OS lock is released even after a process crash; the lock file may remain."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix(path.suffix + ".lock").open("a+b") as stream:
        if stream.tell() == 0:
            stream.write(b"0")
            stream.flush()
        stream.seek(0)
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == "nt":
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream, fcntl.LOCK_UN)


def read_cursor(path: Path, source_id: str) -> int:
    if not path.exists():
        return 0
    state = json.loads(path.read_text(encoding="utf-8"))
    if (state.get("schema_version") != 1 or state.get("table") != "public.orders"
            or state.get("source_id") != source_id
            or state.get("cursor_field") != "order_id"
            or type(state.get("last_order_id")) is not int or state["last_order_id"] < 0):
        raise ValueError("Invalid or mismatched cursor file; refusing an implicit reset")
    return state["last_order_id"]


def save_cursor(path: Path, source_id: str, order_id: int, object_name: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    state = {"schema_version": 1, "table": "public.orders", "source_id": source_id,
             "cursor_field": "order_id", "last_order_id": order_id,
             "last_object": object_name, "updated_at_utc": utc_now()}
    with temporary.open("x", encoding="utf-8", newline="\n") as output:
        json.dump(state, output, indent=2)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, path)


def connect_with_retry(attempts: int = 5, sleep=time.sleep, connect=psycopg.connect):
    if attempts < 1:
        raise ValueError("At least one connection attempt is required")
    for attempt in range(1, attempts + 1):
        try:
            return connect(connect_timeout=5, autocommit=True, row_factory=dict_row,
                           options="-c default_transaction_read_only=on -c statement_timeout=30000")
        except psycopg.OperationalError as error:
            LOGGER.warning("PostgreSQL connection attempt %d/%d failed (%s)",
                           attempt, attempts, type(error).__name__)
            if attempt == attempts:
                raise
            sleep(min(2 ** (attempt - 1), 8))


def fetch_orders(connection, lower: int, upper: int, limit: int) -> list[dict]:
    with connection.cursor() as cursor:
        cursor.execute("SELECT * FROM public.orders WHERE order_id > %s AND order_id <= %s "
                       "ORDER BY order_id LIMIT %s", (lower, upper, limit))
        if [column.name for column in cursor.description] != SCHEMA.names:
            raise ValueError("Orders schema changed; no columns may be silently dropped")
        return cursor.fetchall()


def extract_window(fetch, upper: int, store, state_path: Path, source_id: str,
                   batch_size: int = 5000) -> dict:
    lower = read_cursor(state_path, source_id)
    if upper < lower:
        raise ValueError("Source watermark moved backwards; investigate a source reset")
    rows_written, batches = 0, 0
    while lower < upper:
        rows = fetch(lower, upper, batch_size)
        if not rows:
            break
        ids = [row["order_id"] for row in rows]
        if (ids != sorted(set(ids)) or ids[0] <= lower or ids[-1] > upper
                or any(set(row) != set(SCHEMA.names) for row in rows)):
            raise ValueError("Unexpected order keys/schema; refusing to advance the cursor")
        day = datetime.now(timezone.utc).date().isoformat()
        prefix = f"bronze/python/orders/ingestion_date={day}"
        schema = SCHEMA.with_metadata({b"source_id": source_id.encode("utf-8"),
                                       b"source_table": b"public.orders",
                                       b"cursor_lower_exclusive": str(lower).encode(),
                                       b"cursor_upper_inclusive": str(ids[-1]).encode()})
        name = parquet_object(store, prefix, rows, schema)
        save_cursor(state_path, source_id, ids[-1], name)
        lower = ids[-1]
        rows_written += len(rows)
        batches += 1
    return {"rows": rows_written, "batches": batches, "last_order_id": lower}


def run_once(store, state_path: Path, source_id: str, batch_size: int, attempts: int) -> dict:
    with connect_with_retry(attempts) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT coalesce(max(order_id), 0) AS upper_id FROM public.orders")
            upper = cursor.fetchone()["upper_id"]
        return extract_window(lambda lower, bound, limit: fetch_orders(connection, lower, bound, limit),
                              upper, store, state_path, source_id, batch_size)


INTERVAL_PREFIX = "bronze/scheduled/orders"
LINES_PREFIX = "bronze/scheduled/order_items"
LOAD_ID = re.compile(r"[A-Za-z0-9_.-]{1,64}")
LINES_SCHEMA = pa.schema([
    ("order_id", pa.int64()), ("p_id", pa.string()), ("qty", pa.int64()),
    ("price_at_purchase", pa.decimal128(10, 2)),
])


def fetch_interval(connection, start: date, end: date) -> tuple[list[dict], list[dict]]:
    """Orders of [start, end) and their lines, read from one snapshot of the database."""
    with connection.transaction(), connection.cursor() as cursor:
        # Both reads see the same committed state, so no line can belong to an order
        # that the first read missed.
        cursor.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
        cursor.execute("SELECT * FROM public.orders WHERE order_date >= %s AND order_date < %s "
                       "ORDER BY order_id", (start, end))
        if [column.name for column in cursor.description] != SCHEMA.names:
            raise ValueError("Orders schema changed; no columns may be silently dropped")
        orders = cursor.fetchall()
        cursor.execute("SELECT oi.* FROM public.order_items AS oi JOIN public.orders AS o "
                       "USING (order_id) WHERE o.order_date >= %s AND o.order_date < %s "
                       "ORDER BY oi.order_id, oi.p_id", (start, end))
        if [column.name for column in cursor.description] != LINES_SCHEMA.names:
            raise ValueError("Order lines schema changed; no columns may be silently dropped")
        return orders, cursor.fetchall()


def extract_interval(fetch, start: date, end: date, store, source_id: str, load_id: str,
                     prefix: str = INTERVAL_PREFIX, lines_prefix: str = LINES_PREFIX) -> dict:
    """Write two new objects per day of [start, end), lines then orders. Never overwrites:
    load_id makes each run distinct."""
    if end <= start:
        raise ValueError("The interval end must be after its start")
    if not LOAD_ID.fullmatch(load_id):
        raise ValueError("load_id may only contain letters, digits, '.', '_' and '-'")
    rows, lines = fetch(start, end)
    ids = [row["order_id"] for row in rows]
    if (len(ids) != len(set(ids)) or any(set(row) != set(SCHEMA.names) for row in rows)
            or any(not start <= row["order_date"] < end for row in rows)):
        raise ValueError("Unexpected order keys, columns or dates; refusing to write")
    day_of = {row["order_id"]: row["order_date"] for row in rows}
    keys = [(line["order_id"], line["p_id"]) for line in lines]
    if (len(keys) != len(set(keys)) or any(set(line) != set(LINES_SCHEMA.names) for line in lines)
            or any(line["order_id"] not in day_of for line in lines)):
        raise ValueError("Unexpected order line keys or columns, or a line without its order; "
                         "refusing to write")
    objects, day = [], start
    while day < end:
        # A day with no orders still gets (empty) objects: they record that the run happened.
        # Lines first: an orders object that exists always has its lines object.
        for table, folder, schema, day_rows in (
                ("public.order_items", lines_prefix, LINES_SCHEMA,
                 [line for line in lines if day_of[line["order_id"]] == day]),
                ("public.orders", prefix, SCHEMA, [row for row in rows if row["order_date"] == day])):
            tagged = schema.with_metadata({b"source_id": source_id.encode("utf-8"),
                                           b"source_table": table.encode(),
                                           b"interval_date": day.isoformat().encode(),
                                           b"load_id": load_id.encode()})
            name = f"{folder}/interval_date={day.isoformat()}/load_id={load_id}/part-0.parquet"
            objects.append(parquet_named(store, name, day_rows, tagged))
        day += timedelta(days=1)
    return {"mode": "interval", "interval_start": start.isoformat(), "interval_end": end.isoformat(),
            "load_id": load_id, "rows": len(rows), "lines": len(lines), "objects": len(objects)}


def run_interval(parser: argparse.ArgumentParser, args: argparse.Namespace) -> None:
    if not (args.interval_start and args.interval_end):
        parser.error("Interval mode needs both --interval-start and --interval-end "
                     "(or INTERVAL_START and INTERVAL_END)")
    try:
        start, end = date.fromisoformat(args.interval_start), date.fromisoformat(args.interval_end)
    except ValueError:
        parser.error("Interval dates must be YYYY-MM-DD")
    if end <= start:
        parser.error("The interval end must be after its start")
    for name in ("PGHOST", "PGDATABASE", "PGUSER", "SOURCE_ID"):
        if not os.environ.get(name):
            parser.error(f"Missing environment variable: {name}")
    # The load id only names the run's objects (provenance); it never selects data.
    load_id = args.load_id or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    if not LOAD_ID.fullmatch(load_id):
        parser.error("--load-id may only contain letters, digits, '.', '_' and '-'")
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    try:
        store = make_store(args.local_output)
        with connect_with_retry(args.connection_attempts) as connection:
            result = extract_interval(lambda lo, hi: fetch_interval(connection, lo, hi),
                                      start, end, store, os.environ["SOURCE_ID"], load_id)
        print(json.dumps(result), flush=True)
    except Exception as error:
        # Driver exception text may contain connection details. Log no secrets.
        LOGGER.error("Interval extraction stopped (%s); each day's object is written whole, "
                     "so rerunning the same interval is safe", type(error).__name__)
        raise SystemExit(1) from None


def main() -> None:
    load_environment()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interval-start", default=os.environ.get("INTERVAL_START"),
                        help="Interval mode: first day covered, YYYY-MM-DD (default $INTERVAL_START)")
    parser.add_argument("--interval-end", default=os.environ.get("INTERVAL_END"),
                        help="Interval mode: day after the last one covered (default $INTERVAL_END)")
    parser.add_argument("--load-id", default=os.environ.get("LOAD_ID"),
                        help="Interval mode: name for this run's objects (default: UTC timestamp)")
    parser.add_argument("--once", action="store_true", help="Drain one bounded ID window, then exit")
    parser.add_argument("--batch-size", type=int, default=5000)
    parser.add_argument("--poll-seconds", type=float, default=60)
    parser.add_argument("--connection-attempts", type=int, default=5)
    parser.add_argument("--state-file", type=Path, help="Defaults to data/state/orders.json for GCS")
    parser.add_argument("--local-output", type=Path, help="Local test output instead of GCS")
    args = parser.parse_args()
    if args.interval_start or args.interval_end:
        run_interval(parser, args)
        return
    if args.batch_size < 1 or args.poll_seconds <= 0 or not 1 <= args.connection_attempts <= 10:
        parser.error("Batch/poll values must be positive and connection attempts between 1 and 10")
    default_state = Path("data/state/orders.json")
    if args.local_output is not None and (args.state_file is None or args.state_file.resolve() == default_state.resolve()):
        parser.error("--local-output requires an explicit separate --state-file; never advance the default GCS cursor")
    args.state_file = args.state_file or default_state
    for name in ("PGHOST", "PGDATABASE", "PGUSER", "SOURCE_ID"):
        if not os.environ.get(name):
            parser.error(f"Missing environment variable: {name}")
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    try:
        with state_lock(args.state_file):
            store = make_store(args.local_output)
            while True:
                result = run_once(store, args.state_file, os.environ["SOURCE_ID"],
                                  args.batch_size, args.connection_attempts)
                print(json.dumps(result), flush=True)
                if args.once:
                    break
                time.sleep(args.poll_seconds)
    except KeyboardInterrupt:
        LOGGER.info("Extractor stopped; completed checkpoints are retained")
    except Exception as error:
        # Driver exception text may contain connection details. Log no secrets.
        LOGGER.error("Extraction stopped (%s); retain the last checkpoint and investigate", type(error).__name__)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
