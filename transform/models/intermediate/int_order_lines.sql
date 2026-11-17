-- ONE PLACE where the two order origins meet: one row per line of a real order.
--
--   * Before scheduled_orders_from (2026-09-15): the Step 2 snapshot, with the legacy
--     twin of every order removed by int_orders_deduplicated.
--   * From that day on: the Step 7 scheduled extract (stg_scheduled_orders and its
--     lines), the newest load of each day.
--
-- The twin rule is NOT applied to scheduled orders. The duplicates are a defect of the
-- legacy snapshot; the orders placed since 15 September are single. Checked on the
-- local source on 2026-11-17: of the 2,212 orders from 15 September, 18 payment ids
-- are shared by two orders of the same buyer, and in all 18 the baskets differ, so
-- none is a twin. Applying the rule would drop real orders.
-- The date bounds make each order come from exactly one origin even if a day before
-- the cut-over is ever re-extracted.
with snapshot_lines as (

    select
        items.order_id,
        items.p_id,
        orders.order_date,
        orders.buyer_id,
        items.quantity,
        items.unit_price_eur,
        items.is_zero_price,
        'snapshot'                                         as order_origin
    from {{ ref('stg_order_items') }} as items
    inner join {{ ref('int_orders_deduplicated') }} as orders using (order_id)
    where orders.order_date < date '{{ var("scheduled_orders_from") }}'

),

scheduled_lines as (

    select
        items.order_id,
        items.p_id,
        orders.order_date,
        orders.buyer_id,
        items.quantity,
        items.unit_price_eur,
        items.is_zero_price,
        'scheduled'                                        as order_origin
    from {{ ref('stg_scheduled_order_items') }} as items
    inner join {{ ref('stg_scheduled_orders') }} as orders using (order_id)
    where orders.order_date >= date '{{ var("scheduled_orders_from") }}'

)

select * from snapshot_lines
union all
select * from scheduled_lines
