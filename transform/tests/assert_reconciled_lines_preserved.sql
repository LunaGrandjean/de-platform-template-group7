-- Acceptance check: the country join must not add, drop or repeat order lines,
-- and quantities must still add up to the reconciled silver lines.
--
-- "Reconciled silver lines" = the snapshot lines of the orders that survived
-- deduplication (before the cut-over), plus the scheduled lines (from the
-- cut-over), taken straight from silver with no country or product join.
-- fct_order_items and fct_daily_demand must match it exactly.
-- Fails (returns a row) when any of the three disagree.
with silver_lines as (

    select items.quantity
    from {{ ref('stg_order_items') }} as items
    inner join {{ ref('int_orders_deduplicated') }} as orders using (order_id)
    where orders.order_date < date '{{ var("scheduled_orders_from") }}'

    union all

    select items.quantity
    from {{ ref('stg_scheduled_order_items') }} as items
    inner join {{ ref('stg_scheduled_orders') }} as orders using (order_id)
    where orders.order_date >= date '{{ var("scheduled_orders_from") }}'

),

reconciled as (

    select count(*) as line_count, sum(quantity) as units
    from silver_lines

),

fact_items as (

    select count(*) as line_count, sum(quantity) as units
    from {{ ref('fct_order_items') }}

),

fact_demand as (

    select sum(units_sold) as units
    from {{ ref('fct_daily_demand') }}

)

select
    reconciled.line_count as reconciled_lines,
    fact_items.line_count as fact_lines,
    reconciled.units      as reconciled_units,
    fact_items.units      as fact_item_units,
    fact_demand.units     as fact_demand_units
from reconciled
cross join fact_items
cross join fact_demand
where reconciled.line_count != fact_items.line_count
   or reconciled.units != fact_items.units
   or reconciled.units != fact_demand.units
