-- Source: bronze_ingestion.scheduled_order_items (Step 7 interval extract of
--   public.order_items, written by the marketplace_daily DAG with the orders).
-- FIXES: a rerun adds a newer load instead of overwriting. Lines are kept only when
--   they belong to the load that stg_scheduled_orders kept for their day, so a day's
--   orders and lines always come from the same run. A lines load whose orders were
--   never written (a run that stopped in between) matches nothing and is ignored.
-- FIXES: renames as in stg_order_items: qty -> quantity, price_at_purchase ->
--   unit_price_eur, and is_zero_price flags lines priced 0.00.
-- LEFT ALONE: already typed (INT64 and NUMERIC in the Parquet).
select
    items.order_id,
    trim(items.p_id)                                       as p_id,
    items.qty                                              as quantity,
    cast(items.price_at_purchase as numeric)               as unit_price_eur,
    cast(items.price_at_purchase as numeric) = 0           as is_zero_price,
    items.interval_date,
    items.load_id
from {{ source('bronze_ingestion', 'scheduled_order_items') }} as items
inner join {{ ref('stg_scheduled_orders') }} as orders
    on items.order_id = orders.order_id
   and items.interval_date = orders.interval_date
   and items.load_id = orders.load_id
where items.interval_date >= date '2000-01-01'
