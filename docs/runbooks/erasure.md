# Runbook: erase one person

**Status, 2026-11-20: written, not yet run.** The brief asks for one test on
one real identifier. It permanently changes group data: gold row counts drop,
and the tests that pin exact counts may fail. The group decides first which
buyer, and when. The test record at the end is empty until then, and this line
changes when it is filled.

**Who runs it:** a member who is a fine-grained reader of `pii-identifier`
(docs/governance.md) and can write Bronze, the warehouse and gold. The
warehouse rebuild needs Émile, its only writer after the Step 10 narrowing.

**What you need:** the person's `buyer_id`, which is what an erasure request
resolves to (the company maps a name or an email to it; we never hold
either). Everything below uses `$ID` for it.

```powershell
$ID = "AE...."   # the buyer_id, 28 characters
```

## 1. Find the person: every place the identifier is

From the classification ([governance.md](../governance.md), section 3). A
person is reached through `buyer_id` (and its copies `customer_id`, `c_id`,
`_kafka_key`), and through the addresses linked to them.

| Layer | Where | Column | How to find the rows |
|---|---|---|---|
| Bronze, snapshot (Step 2) | `bronze/snapshot/{orders,review,customer_shipping}/` | `buyer_id`, `c_id` | `_FILE_NAME` on the external tables, query A |
| Bronze, addresses | `bronze/snapshot/shipping_details/` | `address_id`, then `street_address`, `phone`, `city`, `zip` | the person's `address_id` values from `customer_shipping`, query A |
| Bronze, CDC (Step 3) | `bronze/cdc/{orders,review,customer_shipping,shipping_details}/`: 940 files with **no external table** over them | full row images | query B |
| Bronze, Python and scheduled extracts | `bronze/python/orders/`, `bronze/scheduled/orders/` | `buyer_id` | query A on `python_orders`, `scheduled_orders` |
| Bronze, clickstream | `bronze/kafka/clickstream/` | `buyer_id`, `_kafka_key`, and possibly inside `raw_value` | query A on `kafka_clickstream` (needs an `event_date` filter) |
| Warehouse | `g07_warehouse.orders` | `buyer_id` (tagged) | `WHERE buyer_id = $ID` |
| Silver | 9 views | `buyer_id`, `customer_id` | nothing to do: views read Bronze |
| Gold | `g07_gold.fct_order_items` | `buyer_id` (tagged) | `WHERE buyer_id = $ID`; `fct_daily_demand` holds the person only as a count |
| Outside the platform | the source PostgreSQL, the Kafka topic, Airbyte's state, laptops' `data/` folders | everything | not ours: section 6 |

Query A finds the Bronze files that hold the person. Every external table
exposes `_FILE_NAME`:

```sql
-- Query A: one row per Bronze file that holds the person. Save the output: it is the work list.
DECLARE id STRING DEFAULT 'AE....';
SELECT 'orders' t, _FILE_NAME f, COUNT(*) n FROM `data-engineering-i1.g07_bronze.orders` WHERE buyer_id = id GROUP BY 2
UNION ALL SELECT 'python_orders', _FILE_NAME, COUNT(*) FROM `data-engineering-i1.g07_bronze.python_orders` WHERE buyer_id = id GROUP BY 2
UNION ALL SELECT 'scheduled_orders', _FILE_NAME, COUNT(*) FROM `data-engineering-i1.g07_bronze.scheduled_orders` WHERE buyer_id = id GROUP BY 2
UNION ALL SELECT 'review', _FILE_NAME, COUNT(*) FROM `data-engineering-i1.g07_bronze.review` WHERE buyer_id = id GROUP BY 2
UNION ALL SELECT 'customer_shipping', _FILE_NAME, COUNT(*) FROM `data-engineering-i1.g07_bronze.customer_shipping` WHERE c_id = id GROUP BY 2
UNION ALL SELECT 'shipping_details', _FILE_NAME, COUNT(*) FROM `data-engineering-i1.g07_bronze.shipping_details`
  WHERE address_id IN (SELECT address_id FROM `data-engineering-i1.g07_bronze.customer_shipping` WHERE c_id = id) GROUP BY 2
UNION ALL SELECT 'kafka_clickstream', _FILE_NAME, COUNT(*) FROM `data-engineering-i1.g07_bronze.kafka_clickstream`
  WHERE event_date >= '2000-01-01' AND (buyer_id = id OR STRPOS(raw_value, id) > 0) GROUP BY 2;
```

Query B covers the CDC files. No table reads them, so create one for the
search and drop it afterwards:

```sql
-- Query B: a throwaway external table over one CDC prefix (repeat per prefix), then the same _FILE_NAME search.
CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i1.g07_bronze.tmp_erasure_cdc_orders`
OPTIONS (format = 'PARQUET', uris = ['gs://data-engineering-i1-marketplace-group/bronze/cdc/orders/*']);
SELECT t._FILE_NAME f, COUNT(*) n FROM `data-engineering-i1.g07_bronze.tmp_erasure_cdc_orders` AS t
WHERE STRPOS(TO_JSON_STRING(t), 'AE....') > 0 GROUP BY 1;   -- the id anywhere in the row image
DROP EXTERNAL TABLE `data-engineering-i1.g07_bronze.tmp_erasure_cdc_orders`;
```

## 2. Bronze: rewrite the files, by hand

Not automated. For each file in the work list:

1. Download it. Read it with pyarrow and drop the person's rows. Write it back
   with the same name, the same schema and Snappy compression.
2. Check that the row count fell by exactly the number in the work list.
3. Upload it over the original.
4. Run query A again. The count for that file is now 0.

For a buyer in the snapshot only, that is 3 to 6 files of up to 10 MB. CDC
adds one file per change to their rows. Expected time, **not yet measured**:
the test record will say. Two things make Bronze slow:

- **The snapshot is frozen on purpose.** The Step 2 manifest
  (`bronze/_manifests/20261026T105159Z-2efcb86a.json`) holds a checksum of
  every file. A rewritten file no longer matches. Record the erasure in the
  manifest's history, never by silently updating the checksum.
- **Erasing Bronze breaks reproducibility, by design.** Rebuilding gold from
  Bronze no longer gives the Step 2 figures (111,322 orders). The singular
  tests that pin exact counts need the new figure and a comment saying why.

## 3. Warehouse: rebuild, by Émile

```powershell
uv run --locked scripts/warehouse.py native
```

It rebuilds `orders` and `order_lines` from the rewritten Bronze, and puts
`buyer_id`'s policy tag back. Then:

```sql
SELECT COUNT(*) FROM `data-engineering-i1.g07_warehouse.orders` WHERE order_date >= '2000-01-01' AND buyer_id = 'AE....';  -- 0
```

## 4. Silver and gold: one dbt command

```powershell
cd transform; uv run --locked dbt build --selector full
```

Silver is views, so it is clean as soon as Bronze is. `--selector full` (not
`daily`) rebuilds every gold table from them: `fct_order_items` (the person's
lines), `fct_daily_demand` (their units and orders, as counts),
`dim_product.review_count` and `avg_rating`. It also runs the frozen-snapshot
tests that `daily` skips, which is the point: they are the tests an erasure can
break. Expect the count-pinning tests to fail (step 2) and update them in the
same PR.

## 5. The copies that survive

What still holds the person after steps 2 to 4, and for how long. Settings
read on 2026-11-20 ([access-before.json](../evidence/step10/access-before.json)).

| Copy | Setting | How long | What we would have to do |
|---|---|---|---|
| GCS soft delete | `soft_delete_policy` 604,800 s (`infra/terraform/main.tf`) | **7 days** after each overwrite | Wait it out, or have the admin hard-delete the soft-deleted versions. Object versioning is **off**, so no older generation survives beyond that |
| BigQuery time travel | `max_time_travel_hours = 168` on all four datasets | **7 days** | Lower to the 48-hour minimum before erasing (dataset option, `main.tf`), or wait |
| BigQuery fail-safe | fixed by Google, not configurable | **7 more days** after time travel | Nothing; only Google support can read it. The person is fully gone **14 days** after step 4 |
| Old dbt and warehouse tables | `CREATE OR REPLACE` keeps nothing beyond time travel | covered above | none |
| Query results cache | 24 hours, per user | 1 day | none |
| Our evidence files in git | no `buyer_id` in any committed file, checked 2026-11-20 | none | keep it so: evidence is aggregates |
| Laptops' `data/bronze/` folders (Step 2 staging, gitignored) | not managed | until someone deletes them | each member deletes their local copy and says so in the erasure issue |

## 6. Outside our platform

We erase our copies. The source of truth is the company's PostgreSQL. Until it
is erased there, the next CDC event or extract **brings the person back** into
Bronze. The erasure request goes to the source first, then to us. The Kafka
topic keeps events for its retention period, which is the company's setting,
not ours.

## 7. Prove it was done

Write an erasure record in the issue that carried the request, with no
`buyer_id` in it. Use the request's reference number instead.

1. Query A, run again with no rows returned. Save the job id; the job is in
   `INFORMATION_SCHEMA.JOBS` with our labels.
2. The warehouse and gold counts from steps 3 and 4: both 0, with job ids.
3. The list of rewritten objects, with their new generation numbers
   (`gsutil ls -a`, or the console).
4. The date the 14-day window closes (step 4 plus 7 days of time travel plus 7
   of fail-safe). On that date, close the issue.
5. Which copies in section 5 were not handled, and why.

## Test record

| | |
|---|---|
| Date | not yet run |
| Identifier | (request reference, never the buyer_id) |
| Rows found per table | |
| Bronze files rewritten | |
| Time per step | |
| What did not work | |
| 14-day window closes | |
