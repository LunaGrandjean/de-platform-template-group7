-- Source: bronze_ingestion.scheduled_orders (Step 7 interval extract of public.orders,
--   written by the marketplace_daily DAG).
-- FIXES: a rerun of a day never overwrites Bronze; it adds a newer load next to the old
--   one. This model keeps only the newest load per interval_date, so running a day twice
--   changes nothing here (the idempotency mechanism, docs/adr/0007-idempotency.md).
--   The load_id is a UTC timestamp written by the extractor, so the newest sorts last.
-- LEFT ALONE: already typed. It overlaps stg_orders and stg_python_orders (same source
--   table, different extracts), so it is never summed with them.
select
    order_id,
    nullif(trim(buyer_id), '')                             as buyer_id,
    discount_id,
    payment_id,
    order_date,
    interval_date,
    load_id
from {{ source('bronze_ingestion', 'scheduled_orders') }}
where interval_date >= date '2000-01-01'
qualify load_id = max(load_id) over (partition by interval_date)
