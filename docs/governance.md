# Governance: classified, restricted, and erasable (Step 10)

What every column in our warehouse is, who may read it, what we enforced, and
what we could not. The inventory and access checks were measured on 2026-11-20
in the shared project `data-engineering-i1`; dated records are in
[`evidence/step10/`](evidence/step10/). Updated 2026-11-23 to include Émile's
confirmation of the combined Terraform apply on 2026-11-22. Its apply and
final plan transcripts are still to be attached
([source and evidence limits](project-status.md#terraform-apply)).

**The short version.** 196 columns, each with a class and an owner (section 3).
Two columns carry a fine-grained policy tag: `buyer_id` in
`g07_warehouse.orders` and in `g07_gold.fct_order_items`. The two columns that
matter most, the street address and phone in Bronze, **could not be tagged**:
BigQuery refuses policy tags on plain external tables. And we could not show a
refusal from our own accounts, because the course grants every student the
fine-grained read permission at project level. Both gaps are written down in
section 5, with what would close them.

## 1. Classes

| Class | Means | Example |
|---|---|---|
| **public** | Anyone may see it; it is on the storefront or is a calendar | `dim_product.p_name` |
| **internal** | Business data with no personal content | `orders.order_date` |
| **pii.quasi** | Part of an address: harmless alone, identifies a person once joined to a buyer key | `stg_shipping_details.postal_code` |
| **pii.identifier** | A key that points at one person. Pseudonymous, still personal data under GDPR | `buyer_id` |
| **pii.contact** | Reaches a person directly | `shipping_details.phone` |
| **unclassified** | Free text nobody has checked. May contain anything, including the three above | `review.r_desc` |

`unclassified` is not a polite word for "probably fine". A buyer can write
their phone number in a review title, and nothing in the platform would notice.
We treat it like `pii.contact` for access (section 2) until someone scans it.

The owner of a column is the owner of its dataset, because that is the person
who can answer a question about it and who grants access to it:

| Dataset | Owner | Can answer |
|---|---|---|
| `g07_bronze` | Émile (dataOwner) | What was landed, from where, and when |
| `g07_warehouse` | Émile (dataOwner) | The Step 4 typed copies |
| `g07_silver`, `g07_gold` | Malek (dataOwner) | What dbt derives, and the tests that hold it |

## 2. Access matrix

Four roles. "Engineer" is the five of us. "Analyst" is anyone else who can open
the project: other groups, the teacher, a reviewer. "Pipeline" is the
`g07-pipeline` service account once the admin creates it (Step 8); today the
pipeline runs as whichever member's credentials Airflow has.

| Role | public | internal | pii.quasi | pii.identifier | pii.contact | unclassified |
|---|---|---|---|---|---|---|
| **Engineer** (5 members) | read | read | read | read | read | read |
| **Analyst** (anyone else on the project) | read | read | no | no | no | no |
| **Pipeline** (`g07-pipeline`) | read | read, write | read, write | write only | no | read, write |
| **Course admin** (project owners) | read | read | read | no | no | no |

The pipeline writes `buyer_id` into gold but never needs to read it back. The
marts and the tests count rows instead, so the service account gets no
fine-grained read. Section 4 checked that.

**When the answer is "no", the way in:**

| Role, class | Route |
|---|---|
| Analyst, pii.quasi / pii.identifier | Ask for an aggregate first: `fct_daily_demand` and `dim_country` answer most questions without a person in them. If a row-level answer is really needed, open an issue on this repo saying what, why and for how long. The dataset owner adds you to the tag's readers in `infra/terraform/variables.tf` (`pii_readers`) through a reviewed PR, and a second PR removes you on the date you gave. |
| Analyst, pii.contact / unclassified | No route by default. A contact column is needed only to contact someone, which is the company's job, not the data platform's. Unclassified text can be read once it has been scanned and reclassified. |
| Pipeline, pii.identifier read | Same PR route, with the job that needs it named. Nothing does today. |
| Pipeline, pii.contact | None. Silver drops these columns (`stg_shipping_details`), so no model needs them. |
| Course admin, pii.identifier / pii.contact | The admin can grant themselves anything; the route is to ask us, so the grant is recorded here. Section 5 is honest about what that is worth. |

## 3. Classification policy: every column

Generated from `INFORMATION_SCHEMA.COLUMNS` of the four datasets on 2026-11-20
([column-inventory.json](evidence/step10/column-inventory.json)): 34 tables and
views, 196 columns. Totals: public 46, internal 108, pii.quasi 13,
pii.identifier 20, pii.contact 2, unclassified 7. A new column is unclassified
until a PR adds it here.

#### `g07_bronze` (owner: Émile)

| Table | Column | Class | Why | Policy tag |
|---|---|---|---|---|
| `customer_shipping` | `address_id` | pii.quasi | part of an address: identifies a person once joined to a buyer key |  |
| `customer_shipping` | `c_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `customer_shipping` | `is_default` | internal | business data with no personal content |  |
| `kafka_clickstream` | `schema_version` | internal | business data with no personal content |  |
| `kafka_clickstream` | `event_id` | internal | business data with no personal content |  |
| `kafka_clickstream` | `event_type` | internal | business data with no personal content |  |
| `kafka_clickstream` | `event_time` | internal | business data with no personal content |  |
| `kafka_clickstream` | `emitted_at` | internal | business data with no personal content |  |
| `kafka_clickstream` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `kafka_clickstream` | `session_id` | pii.identifier | a key to one visit by one person |  |
| `kafka_clickstream` | `raw_value` | unclassified | the raw event payload as received; its fields are not checked |  |
| `kafka_clickstream` | `_kafka_topic` | internal | business data with no personal content |  |
| `kafka_clickstream` | `_kafka_partition` | internal | business data with no personal content |  |
| `kafka_clickstream` | `_kafka_offset` | internal | business data with no personal content |  |
| `kafka_clickstream` | `_kafka_key` | pii.identifier | the Kafka message key: equals buyer_id on all 29,144 events (checked 2026-11-20) |  |
| `kafka_clickstream` | `_kafka_timestamp_ms` | internal | business data with no personal content |  |
| `kafka_clickstream` | `_ingested_at` | internal | business data with no personal content |  |
| `kafka_clickstream` | `event_date` | internal | business data with no personal content |  |
| `order_items` | `order_id` | internal | business data with no personal content |  |
| `order_items` | `p_id` | public | shown on the storefront to anyone |  |
| `order_items` | `qty` | internal | business data with no personal content |  |
| `order_items` | `price_at_purchase` | internal | business data with no personal content |  |
| `orders` | `order_id` | internal | business data with no personal content |  |
| `orders` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `orders` | `discount_id` | internal | business data with no personal content |  |
| `orders` | `payment_id` | internal | a pointer to a payment record (the source holds card numbers); the id itself reveals nothing |  |
| `orders` | `order_date` | internal | business data with no personal content |  |
| `product` | `p_id` | public | shown on the storefront to anyone |  |
| `product` | `p_name` | public | shown on the storefront to anyone |  |
| `product` | `p_desc` | unclassified | free text written by a seller; nobody has checked what it holds |  |
| `product` | `price` | public | shown on the storefront to anyone |  |
| `product` | `qty` | internal | business data with no personal content |  |
| `product` | `category_id` | public | shown on the storefront to anyone |  |
| `product_reviews` | `p_id` | public | shown on the storefront to anyone |  |
| `product_reviews` | `review_id` | public | shown on the storefront to anyone |  |
| `python_orders` | `order_id` | internal | business data with no personal content |  |
| `python_orders` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `python_orders` | `discount_id` | internal | business data with no personal content |  |
| `python_orders` | `payment_id` | internal | a pointer to a payment record (the source holds card numbers); the id itself reveals nothing |  |
| `python_orders` | `order_date` | internal | business data with no personal content |  |
| `python_orders` | `ingestion_date` | internal | business data with no personal content |  |
| `review` | `review_id` | public | shown on the storefront to anyone |  |
| `review` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `review` | `r_desc` | unclassified | free text written by a buyer; may contain names, addresses, anything |  |
| `review` | `title` | unclassified | free text written by a buyer; may contain names, addresses, anything |  |
| `review` | `rating` | public | shown on the storefront to anyone |  |
| `review` | `seller_product_flag` | internal | business data with no personal content |  |
| `scheduled_order_items` | `order_id` | internal | business data with no personal content |  |
| `scheduled_order_items` | `p_id` | public | shown on the storefront to anyone |  |
| `scheduled_order_items` | `qty` | internal | business data with no personal content |  |
| `scheduled_order_items` | `price_at_purchase` | internal | business data with no personal content |  |
| `scheduled_order_items` | `interval_date` | internal | business data with no personal content |  |
| `scheduled_order_items` | `load_id` | internal | business data with no personal content |  |
| `scheduled_orders` | `order_id` | internal | business data with no personal content |  |
| `scheduled_orders` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `scheduled_orders` | `discount_id` | internal | business data with no personal content |  |
| `scheduled_orders` | `payment_id` | internal | a pointer to a payment record (the source holds card numbers); the id itself reveals nothing |  |
| `scheduled_orders` | `order_date` | internal | business data with no personal content |  |
| `scheduled_orders` | `interval_date` | internal | business data with no personal content |  |
| `scheduled_orders` | `load_id` | internal | business data with no personal content |  |
| `shipping_details` | `address_id` | pii.quasi | part of an address: identifies a person once joined to a buyer key |  |
| `shipping_details` | `street_address` | pii.contact | directly reaches a person: where they live, how to call them | tag refused (external) |
| `shipping_details` | `city` | pii.quasi | part of an address: identifies a person once joined to a buyer key |  |
| `shipping_details` | `state` | pii.quasi | part of an address: identifies a person once joined to a buyer key |  |
| `shipping_details` | `zip` | pii.quasi | part of an address: identifies a person once joined to a buyer key |  |
| `shipping_details` | `country` | pii.quasi | part of an address |  |
| `shipping_details` | `phone` | pii.contact | directly reaches a person: where they live, how to call them | tag refused (external) |

#### `g07_warehouse` (owner: Émile)

| Table | Column | Class | Why | Policy tag |
|---|---|---|---|---|
| `daily_demand` | `order_date` | internal | business data with no personal content |  |
| `daily_demand` | `p_id` | public | shown on the storefront to anyone |  |
| `daily_demand` | `units` | internal | business data with no personal content |  |
| `order_lines` | `order_id` | internal | business data with no personal content |  |
| `order_lines` | `p_id` | public | shown on the storefront to anyone |  |
| `order_lines` | `qty` | internal | business data with no personal content |  |
| `order_lines` | `price_at_purchase` | internal | business data with no personal content |  |
| `order_lines` | `order_date` | internal | business data with no personal content |  |
| `orders` | `order_id` | internal | business data with no personal content |  |
| `orders` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR | **tagged, enforced** |
| `orders` | `discount_id` | internal | business data with no personal content |  |
| `orders` | `payment_id` | internal | a pointer to a payment record (the source holds card numbers); the id itself reveals nothing |  |
| `orders` | `order_date` | internal | business data with no personal content |  |

#### `g07_silver` (owner: Malek)

| Table | Column | Class | Why | Policy tag |
|---|---|---|---|---|
| `int_buyer_country` | `customer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `int_buyer_country` | `country_code` | internal | the buyer's country, next to customer_id: coarse, but about a person |  |
| `int_buyer_country` | `country_name` | internal | the buyer's country, next to customer_id: coarse, but about a person |  |
| `int_order_lines` | `order_id` | internal | business data with no personal content |  |
| `int_order_lines` | `p_id` | public | shown on the storefront to anyone |  |
| `int_order_lines` | `order_date` | internal | business data with no personal content |  |
| `int_order_lines` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `int_order_lines` | `quantity` | internal | business data with no personal content |  |
| `int_order_lines` | `unit_price_eur` | internal | business data with no personal content |  |
| `int_order_lines` | `is_zero_price` | internal | business data with no personal content |  |
| `int_order_lines` | `order_origin` | internal | business data with no personal content |  |
| `int_orders_deduplicated` | `order_id` | internal | business data with no personal content |  |
| `int_orders_deduplicated` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `int_orders_deduplicated` | `payment_id` | internal | a pointer to a payment record (the source holds card numbers); the id itself reveals nothing |  |
| `int_orders_deduplicated` | `order_date` | internal | business data with no personal content |  |
| `int_product_review_stats` | `p_id` | public | shown on the storefront to anyone |  |
| `int_product_review_stats` | `review_count` | public | shown on the storefront to anyone |  |
| `int_product_review_stats` | `rated_review_count` | public | shown on the storefront to anyone |  |
| `int_product_review_stats` | `avg_rating` | public | shown on the storefront to anyone |  |
| `stg_customer_shipping` | `address_id` | pii.quasi | part of an address: identifies a person once joined to a buyer key |  |
| `stg_customer_shipping` | `customer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `stg_customer_shipping` | `is_default` | internal | business data with no personal content |  |
| `stg_kafka_clickstream` | `event_id` | internal | business data with no personal content |  |
| `stg_kafka_clickstream` | `event_type` | internal | business data with no personal content |  |
| `stg_kafka_clickstream` | `event_at` | internal | business data with no personal content |  |
| `stg_kafka_clickstream` | `emitted_at` | internal | business data with no personal content |  |
| `stg_kafka_clickstream` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `stg_kafka_clickstream` | `session_id` | pii.identifier | a key to one visit by one person |  |
| `stg_kafka_clickstream` | `ingested_at` | internal | business data with no personal content |  |
| `stg_kafka_clickstream` | `event_date` | internal | business data with no personal content |  |
| `stg_kafka_clickstream` | `kafka_topic` | internal | business data with no personal content |  |
| `stg_kafka_clickstream` | `kafka_partition` | internal | business data with no personal content |  |
| `stg_kafka_clickstream` | `kafka_offset` | internal | business data with no personal content |  |
| `stg_order_items` | `order_id` | internal | business data with no personal content |  |
| `stg_order_items` | `p_id` | public | shown on the storefront to anyone |  |
| `stg_order_items` | `quantity` | internal | business data with no personal content |  |
| `stg_order_items` | `unit_price_eur` | internal | business data with no personal content |  |
| `stg_order_items` | `is_zero_price` | internal | business data with no personal content |  |
| `stg_orders` | `order_id` | internal | business data with no personal content |  |
| `stg_orders` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `stg_orders` | `discount_id` | internal | business data with no personal content |  |
| `stg_orders` | `payment_id` | internal | a pointer to a payment record (the source holds card numbers); the id itself reveals nothing |  |
| `stg_orders` | `order_date` | internal | business data with no personal content |  |
| `stg_product` | `p_id` | public | shown on the storefront to anyone |  |
| `stg_product` | `p_name` | public | shown on the storefront to anyone |  |
| `stg_product` | `p_desc` | unclassified | free text written by a seller; nobody has checked what it holds |  |
| `stg_product` | `price_eur` | public | shown on the storefront to anyone |  |
| `stg_product` | `stock_qty` | internal | business data with no personal content |  |
| `stg_product` | `category_id` | public | shown on the storefront to anyone |  |
| `stg_product_reviews` | `p_id` | public | shown on the storefront to anyone |  |
| `stg_product_reviews` | `review_id` | public | shown on the storefront to anyone |  |
| `stg_python_orders` | `order_id` | internal | business data with no personal content |  |
| `stg_python_orders` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `stg_python_orders` | `discount_id` | internal | business data with no personal content |  |
| `stg_python_orders` | `payment_id` | internal | a pointer to a payment record (the source holds card numbers); the id itself reveals nothing |  |
| `stg_python_orders` | `order_date` | internal | business data with no personal content |  |
| `stg_python_orders` | `ingestion_date` | internal | business data with no personal content |  |
| `stg_review` | `review_id` | public | shown on the storefront to anyone |  |
| `stg_review` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `stg_review` | `review_text` | unclassified | free text written by a buyer; may contain names, addresses, anything |  |
| `stg_review` | `title` | unclassified | free text written by a buyer; may contain names, addresses, anything |  |
| `stg_review` | `rating` | public | shown on the storefront to anyone |  |
| `stg_review` | `seller_product_flag` | internal | business data with no personal content |  |
| `stg_scheduled_order_items` | `order_id` | internal | business data with no personal content |  |
| `stg_scheduled_order_items` | `p_id` | public | shown on the storefront to anyone |  |
| `stg_scheduled_order_items` | `quantity` | internal | business data with no personal content |  |
| `stg_scheduled_order_items` | `unit_price_eur` | internal | business data with no personal content |  |
| `stg_scheduled_order_items` | `is_zero_price` | internal | business data with no personal content |  |
| `stg_scheduled_order_items` | `interval_date` | internal | business data with no personal content |  |
| `stg_scheduled_order_items` | `load_id` | internal | business data with no personal content |  |
| `stg_scheduled_orders` | `order_id` | internal | business data with no personal content |  |
| `stg_scheduled_orders` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR |  |
| `stg_scheduled_orders` | `discount_id` | internal | business data with no personal content |  |
| `stg_scheduled_orders` | `payment_id` | internal | a pointer to a payment record (the source holds card numbers); the id itself reveals nothing |  |
| `stg_scheduled_orders` | `order_date` | internal | business data with no personal content |  |
| `stg_scheduled_orders` | `interval_date` | internal | business data with no personal content |  |
| `stg_scheduled_orders` | `load_id` | internal | business data with no personal content |  |
| `stg_shipping_details` | `address_id` | pii.quasi | part of an address: identifies a person once joined to a buyer key |  |
| `stg_shipping_details` | `city` | pii.quasi | part of an address: identifies a person once joined to a buyer key |  |
| `stg_shipping_details` | `region` | pii.quasi | part of an address: identifies a person once joined to a buyer key |  |
| `stg_shipping_details` | `postal_code` | pii.quasi | part of an address: identifies a person once joined to a buyer key |  |
| `stg_shipping_details` | `country_name` | pii.quasi | part of an address |  |
| `stg_shipping_details` | `country_code` | pii.quasi | part of an address |  |

#### `g07_gold` (owner: Malek)

| Table | Column | Class | Why | Policy tag |
|---|---|---|---|---|
| `dim_country` | `country_code` | public | a calendar or a country list |  |
| `dim_country` | `country_name` | public | a calendar or a country list |  |
| `dim_date` | `date_day` | public | a calendar or a country list |  |
| `dim_date` | `year` | public | a calendar or a country list |  |
| `dim_date` | `month` | public | a calendar or a country list |  |
| `dim_date` | `day_of_month` | public | a calendar or a country list |  |
| `dim_date` | `iso_week` | public | a calendar or a country list |  |
| `dim_date` | `iso_year` | public | a calendar or a country list |  |
| `dim_date` | `day_of_week` | public | a calendar or a country list |  |
| `dim_date` | `is_weekend` | public | a calendar or a country list |  |
| `dim_product` | `p_id` | public | shown on the storefront to anyone |  |
| `dim_product` | `p_name` | public | shown on the storefront to anyone |  |
| `dim_product` | `price_eur` | public | shown on the storefront to anyone |  |
| `dim_product` | `stock_qty` | internal | business data with no personal content |  |
| `dim_product` | `category_id` | public | shown on the storefront to anyone |  |
| `dim_product` | `review_count` | public | shown on the storefront to anyone |  |
| `dim_product` | `avg_rating` | public | shown on the storefront to anyone |  |
| `fct_daily_demand` | `p_id` | public | shown on the storefront to anyone |  |
| `fct_daily_demand` | `country_code` | public | a calendar or a country list |  |
| `fct_daily_demand` | `order_date` | internal | business data with no personal content |  |
| `fct_daily_demand` | `units_sold` | internal | business data with no personal content |  |
| `fct_daily_demand` | `orders` | internal | business data with no personal content |  |
| `fct_daily_demand` | `gross_revenue_eur` | internal | business data with no personal content |  |
| `fct_order_items` | `order_id` | internal | business data with no personal content |  |
| `fct_order_items` | `p_id` | public | shown on the storefront to anyone |  |
| `fct_order_items` | `order_date` | internal | business data with no personal content |  |
| `fct_order_items` | `buyer_id` | pii.identifier | a key to one buyer; pseudonymous, still personal data under GDPR | **tagged, enforced** |
| `fct_order_items` | `country_code` | internal | the buyer's country, next to buyer_id: coarse, but about a person |  |
| `fct_order_items` | `quantity` | internal | business data with no personal content |  |
| `fct_order_items` | `unit_price_eur` | internal | business data with no personal content |  |
| `fct_order_items` | `gross_amount_eur` | internal | business data with no personal content |  |
| `fct_order_items` | `is_zero_price` | internal | business data with no personal content |  |
| `fct_order_items` | `order_origin` | internal | business data with no personal content |  |

## 4. Hardening: what we changed

**Before touching anything, we found out what reads it.** The tag applies the
moment it lands, to everybody. `INFORMATION_SCHEMA.JOBS` for the 30 days to
2026-11-20 ([readers-30-days.json](evidence/step10/readers-30-days.json)) shows
that only the five members read any `g07_*` table: no other group, no service
account. `fct_order_items` is read by dbt only (`fct_daily_demand` and three
singular tests). We checked their SQL, and none selects `buyer_id`: they use
`count(*)`, `order_id` and `quantity`. `g07_warehouse.orders` was last read on
2026-11-06, by hand. So tagging `buyer_id` in both could not break the
pipeline, and the next dbt build proved it.

| What | Where | State |
|---|---|---|
| Taxonomy `g07-marketplace-classification`, fine-grained access control on, with tags `pii-identifier` and `pii-contact` | [`infra/terraform/governance.tf`](../infra/terraform/governance.tf). Created through the API ([taxonomy-created.json](evidence/step10/taxonomy-created.json)), because `apply` needs Terraform 1.17; [`imports.tf`](../infra/terraform/imports.tf) adopts it at the next apply | live |
| `pii-identifier` on `g07_warehouse.orders.buyer_id` | applied once by hand ([warehouse-tagged.json](evidence/step10/warehouse-tagged.json)). On every rebuild, [`scripts/warehouse.py`](../scripts/warehouse.py) creates `orders` **empty**, tags `buyer_id`, and only then inserts the rows. A failed tag stops the run with an empty table, so the column is never readable untagged. Five unit tests cover it | live |
| `pii-identifier` on `g07_gold.fct_order_items.buyer_id` | [`marts.yml`](../transform/models/marts/marts.yml): `policy_tags`, applied by dbt on every build through `persist_docs: columns` | live. `dbt build -s fct_order_items+` passed 25 of 25 after it. The DAG now defaults to `2026-11-22-c565e73`, built from this branch, so its builds keep the tag. The previous image `2026-11-17-e8df6e5` had no `policy_tags` and would have dropped it. Confirmed 2026-11-22: two DAG runs on it rebuilt `fct_order_items` and the tag stayed on ([dag-run-new-image.txt](evidence/step10/dag-run-new-image.txt)) |
| `pii-contact` on `g07_bronze.shipping_details.street_address` and `phone` | attempted | **refused** by BigQuery ([bronze-tag-refused.json](evidence/step10/bronze-tag-refused.json)), section 5 |
| Fine-grained readers on both tags: the five members, nobody else | `pii_readers` in `governance.tf`; set through the API ([reader-grants.json](evidence/step10/reader-grants.json)) | live |
| Step 9 labels still on every table | [tags-and-labels-after.json](evidence/step10/tags-and-labels-after.json) | gold keeps all four keys after the rebuild. `g07_warehouse.orders` still has its Step 4 labels until `warehouse.py` next rebuilds it |

### The narrowed grant

On `g07_warehouse`, the four members other than Émile go from **dataEditor to
dataViewer** ([`iam.tf`](../infra/terraform/iam.tf), `warehouse_readers`).

- **Why:** the Step 4 loads are finished, and only the owner rebuilds the
  warehouse. An editor can overwrite or drop `orders`, including the rows an
  erasure has just removed or the table that proves it.
- **How it applies:** a `moved` block in
  [`imports.tf`](../infra/terraform/imports.tf) renames `warehouse_writers`,
  already in state since the Step 8 apply, to `warehouse_readers`, which says
  dataViewer. `role` forces replacement, so the read-only plan
  ([terraform-plan.txt](evidence/step10/terraform-plan.txt)) shows `-/+` for
  each of the four members. That replace is the narrowing, in one apply, with
  nothing done by hand. The same plan imports the taxonomy and both tags with
  no diff: `3 to import, 14 to add, 5 to change, 4 to destroy`, of which the
  5 changes are Step 9's labels.
- **Applied, per operator confirmation:** on 2026-11-22 Émile reported the
  combined Step 9 + 10 apply, verified the four warehouse `dataViewer` grants
  in GCP, imported the taxonomy and tags, applied the five members' tag-reader
  access, and obtained a final plan with no changes. The older plan above is
  kept as pre-apply evidence; the apply and final plan transcripts are not yet
  committed ([project status](project-status.md#terraform-apply)).
- **Effective access remains broader:** reducing these named dataset grants
  does not remove inherited project write permissions or course-wide
  fine-grained read access. The refusal check in section 5 is still pending.
- **Writing again:** ask Émile for a time-boxed dataEditor through a PR on
  `iam.tf`, and revert it afterwards.

## 5. Where the matrix and reality differ

A documented gap is a finding. These are ours, worst first.

1. **The contact data cannot be protected where it lives.**
   - Street address and phone exist only in Bronze: 3 snapshot Parquet files
     behind the external table `g07_bronze.shipping_details`, and 107 CDC
     files under `bronze/cdc/shipping_details/`.
   - BigQuery answered *"Policy tags are not supported on plain external
     tables. Use a BigLake table instead."* A BigLake table needs a BigQuery
     connection, and `bigquery.connections.list` is already refused to us
     (403).
   - So anyone with read on `g07_bronze` can read every phone number. Today
     that includes `projectReaders`, the whole course. The bucket gives
     `projectViewer` object read too
     ([access-before.json](evidence/step10/access-before.json)).
   - **What would close it, in order:**
     1. Stop landing these two columns. Silver drops them and nothing
        downstream uses them, so the extractor should leave them in the
        source.
     2. Ask the admin for a BigLake connection.
     3. Ask the admin to remove `projectReaders` from `g07_bronze` and
        `projectViewer` from the bucket.
2. **Enforcement could not be shown by a refusal.**
   - After tagging, our own queries of `buyer_id` were **served**, twice, a
     minute apart ([read-checks.json](evidence/step10/read-checks.json)).
   - The tag's IAM policy was empty, yet `testIamPermissions` showed that we
     hold `datacatalog.categories.fineGrainedGet`, plus `taxonomies.delete`
     and `setIamPolicy`. They are inherited from above the taxonomy,
     presumably a project-level grant so every group could run the course
     demo.
   - The matrix requires an analyst to be denied `pii.identifier`. We still
     need an identity with table access but no explicit or inherited
     fine-grained tag-reader permission to verify that requirement. Émile
     confirmed the same limitation after the 2026-11-22 apply; the group
     cannot create a separate service account to test it.
   - **What would close it:** someone outside the course's student grant (the
     admin, or a test account) runs
     `SELECT buyer_id FROM g07_gold.fct_order_items LIMIT 1` and should get
     *"User has neither fine-grained reader nor masked get permission"*. Or
     the admin drops the project-level grant, and we rerun the same query
     from a member removed from `pii_readers`.
3. **Two of the twenty `pii.identifier` columns are enforced.**
   - Silver is views, which cannot carry tags, and Bronze is external tables.
   - So `buyer_id` is protected in the two native tables and readable through
     `g07_silver.stg_orders`, `int_order_lines` and the Bronze tables.
   - **What would close it:** materialise the silver models that carry a buyer
     key as tables, so they can be tagged. That is a Step 5 decision (ADR 0005)
     with a storage cost nobody has measured yet.
4. **Anyone with the project-level Data Catalog role can delete our taxonomy.**
   - It is the dangerous half of gap 2: one API call and both tagged columns
     become readable again, while their schemas still show the tag.
   - The only reliable check is the refusal test in gap 2, run on a schedule.
     Reading the schema proves nothing.
5. **We cannot see who read a column.**
   - The BigQuery Data Access log returned 0 entries to our accounts. It is a
     private log, and we lack `logging.privateLogEntries.list`
     ([audit-log-check.json](evidence/step10/audit-log-check.json)).
   - The Admin Activity log is visible and records both tagging changes, by
     member.
   - Who read which *table* comes from `INFORMATION_SCHEMA.JOBS`. Who was
     refused, or who read which *column*, is the admin's to see.
6. **pii.quasi and unclassified are not enforced at all.**
   - The address parts in silver, the review text and the raw clickstream
     payload are readable by anyone with dataset access.
   - Unclassified text needs a scan first: the DLP API, which the admin would
     have to enable.
7. **Project default bindings stay.**
   - `projectOwners`, `projectWriters` and `projectReaders` sit on every
     dataset; the same for the bucket.
   - They belong to the admin, and declaring them in our state would let our
     `apply` change other groups' access.

## 6. Checking it again

```powershell
# 1. Which columns carry a tag (reads schemas: shows intent, not enforcement)
uv run --locked python -c "from google.cloud import bigquery; c=bigquery.Client(project='data-engineering-i1'); [print(t, f.name, f.policy_tags.names) for t in ['g07_warehouse.orders','g07_gold.fct_order_items'] for f in c.get_table(t).schema if f.policy_tags and f.policy_tags.names]"
```

```powershell
# 2. Enforcement, the only real check: from an account NOT in pii_readers and without the course-wide grant
bq query --use_legacy_sql=false "SELECT buyer_id FROM data-engineering-i1.g07_gold.fct_order_items LIMIT 1"
```

```powershell
# 3. Who reads our tables, last 30 days
bq query --use_legacy_sql=false "SELECT user_email, r.table_id, COUNT(*) jobs FROM ``region-europe-west1``.INFORMATION_SCHEMA.JOBS, UNNEST(referenced_tables) r WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY) AND STARTS_WITH(r.dataset_id, 'g07_') GROUP BY 1, 2 ORDER BY 3 DESC"
```

Why access is decided by classification at all, and not by a view per
consumer or a dataset per sensitivity level: [ADR 0010](adr/0010-data-classification.md).
How a person is erased: [runbooks/erasure.md](runbooks/erasure.md).
