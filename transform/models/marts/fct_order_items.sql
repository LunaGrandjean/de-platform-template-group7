-- One row per order line of a real order, from int_order_lines: the snapshot (legacy
-- twins already removed) before 2026-09-15, the scheduled daily extract from then on.
-- Each line carries its buyer's single default-address country. A buyer with no known
-- address gets the UNKNOWN member of dim_country instead of being dropped: since the
-- scheduled extract started, new buyers can have no address in the snapshot (46 of the
-- first 2,208 scheduled orders, 45 of whose buyers have no address in the source at all).
-- Zero-priced lines are kept: they count in units and add 0 to the amount.
-- gross_amount_eur = quantity x price at purchase, BEFORE any discount (every
-- discount_id is empty in the source) and with NO returns subtracted (the
-- returns table is empty). It is a gross figure, not net revenue.
select
    lines.order_id,
    lines.p_id,
    lines.order_date,
    lines.buyer_id,
    coalesce(country.country_code, 'UNKNOWN')              as country_code,
    lines.quantity,
    lines.unit_price_eur,
    lines.quantity * lines.unit_price_eur                  as gross_amount_eur,
    lines.is_zero_price,
    lines.order_origin
from {{ ref('int_order_lines') }} as lines
left join {{ ref('int_buyer_country') }} as country
    on lines.buyer_id = country.customer_id
