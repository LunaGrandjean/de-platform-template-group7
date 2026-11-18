-- Step 7 acceptance check: a new order that the scheduled run lands in silver must
-- reach gold, with all of its lines.
--
-- For every order in stg_scheduled_orders dated from the cut-over, compare its
-- silver lines and units with its rows in fct_order_items. Returns (and so fails on)
-- any order that is missing from gold, has no lines, or lost or gained a line or a
-- unit on the way. An order with no lines in silver is returned too: it could never
-- reach a line-grain fact, and a person should look at it.
with silver as (

    select
        orders.order_id,
        count(items.p_id)                                  as silver_lines,
        coalesce(sum(items.quantity), 0)                   as silver_units
    from {{ ref('stg_scheduled_orders') }} as orders
    left join {{ ref('stg_scheduled_order_items') }} as items using (order_id)
    where orders.order_date >= date '{{ var("scheduled_orders_from") }}'
    group by orders.order_id

),

gold as (

    select order_id, count(*) as gold_lines, sum(quantity) as gold_units
    from {{ ref('fct_order_items') }}
    where order_origin = 'scheduled'
    group by order_id

)

select
    silver.order_id,
    silver.silver_lines,
    gold.gold_lines,
    silver.silver_units,
    gold.gold_units
from silver
left join gold using (order_id)
where silver.silver_lines = 0
   or gold.order_id is null
   or gold.gold_lines != silver.silver_lines
   or gold.gold_units != silver.silver_units
