-- One row per market, plus UNKNOWN. Markets come from the addresses, so a country
-- appears here only if a customer lives in it. UNKNOWN is where fct_order_items puts
-- an order whose buyer has no known default address (acceptance criteria, D2).
select distinct
    country_code,
    country_name
from {{ ref('stg_shipping_details') }}
where country_code is not null

union all

select 'UNKNOWN' as country_code, 'Unknown' as country_name
