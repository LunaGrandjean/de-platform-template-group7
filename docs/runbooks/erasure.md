# Runbook: erase one person

**Status, 2026-11-21: run once, on one real buyer, and it worked.**
- **The buyer:** one order, two lines, from the Step 7 scheduled extract.
- **Result:** gone from Bronze, silver and gold. dbt passed 102 of 103 after the
  rebuild, with the known `p_name` warning.
- **Where it can come back from:** the source database, whose erasure is the
  company's job (section 6).

The run found two mistakes in the first version of this runbook, both now
fixed below. The test record at the end has the numbers.

**Who runs it:** a member with three permissions:
- fine-grained reader of `pii-identifier` (docs/governance.md)
- object write on the bucket
- write on `g07_warehouse` (for the throwaway tables in query B, and the
  rebuild)

After the Step 10 narrowing, that last one is Émile. The 2026-11-21 test ran
before the narrowing was applied.

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
| Bronze, CDC (Step 3) | `bronze/cdc/{orders,order_items,review,customer_shipping,shipping_details}/`: about 1,700 files with **no external table** over them | Debezium messages: the row in `raw_value` (`$.after`, `$.before`), its key in `raw_key`; both BYTES | query B |
| Bronze, the person's order lines | `bronze/scheduled/order_items/`, `bronze/cdc/order_items/`, `bronze/snapshot/order_items/` | no `buyer_id`: found through the person's `order_id`s | query A, then B, with the order ids from the first rows |
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
UNION ALL SELECT 'python_orders', _FILE_NAME, COUNT(*) FROM `data-engineering-i1.g07_bronze.python_orders` WHERE ingestion_date >= '2000-01-01' AND buyer_id = id GROUP BY 2
UNION ALL SELECT 'scheduled_orders', _FILE_NAME, COUNT(*) FROM `data-engineering-i1.g07_bronze.scheduled_orders` WHERE interval_date >= '2000-01-01' AND buyer_id = id GROUP BY 2
UNION ALL SELECT 'review', _FILE_NAME, COUNT(*) FROM `data-engineering-i1.g07_bronze.review` WHERE buyer_id = id GROUP BY 2
UNION ALL SELECT 'customer_shipping', _FILE_NAME, COUNT(*) FROM `data-engineering-i1.g07_bronze.customer_shipping` WHERE c_id = id GROUP BY 2
UNION ALL SELECT 'shipping_details', _FILE_NAME, COUNT(*) FROM `data-engineering-i1.g07_bronze.shipping_details`
  WHERE address_id IN (SELECT address_id FROM `data-engineering-i1.g07_bronze.customer_shipping` WHERE c_id = id) GROUP BY 2
UNION ALL SELECT 'kafka_clickstream', _FILE_NAME, COUNT(*) FROM `data-engineering-i1.g07_bronze.kafka_clickstream`
  WHERE event_date >= '2000-01-01' AND (buyer_id = id OR STRPOS(raw_value, id) > 0) GROUP BY 2;
```

`python_orders`, `scheduled_orders` and `kafka_clickstream` refuse a query
without a partition filter. The first version of this query forgot two of
them and failed on the first run. Then repeat the scheduled and snapshot
`order_items` lines with `CAST(order_id AS STRING) IN (...)`, using the order ids
the orders rows gave.

Query B covers the CDC files. No table reads them, so create one per prefix in
`g07_warehouse` for the search, and drop it afterwards. `raw_value` and
`raw_key` are BYTES, and the row sits under `after` (or `before`, for an update
or a delete). The first version searched `TO_JSON_STRING` of the whole row,
which sees base64, not the id, and would have found nothing:

```sql
-- Query B, per prefix (orders shown; order_items by order_id, customer_shipping by c_id, shipping_details by address_id).
CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i1.g07_warehouse.tmp_erasure_cdc_orders`
OPTIONS (format = 'PARQUET', uris = ['gs://data-engineering-i1-marketplace-group/bronze/cdc/orders/*']);
SELECT _FILE_NAME f, COUNT(*) n FROM `data-engineering-i1.g07_warehouse.tmp_erasure_cdc_orders`
WHERE COALESCE(JSON_VALUE(SAFE_CONVERT_BYTES_TO_STRING(raw_value), '$.after.buyer_id'),
               JSON_VALUE(SAFE_CONVERT_BYTES_TO_STRING(raw_value), '$.before.buyer_id')) = 'AE....'
GROUP BY 1;
DROP EXTERNAL TABLE `data-engineering-i1.g07_warehouse.tmp_erasure_cdc_orders`;
```

## 2. Bronze: rewrite the files, by hand

Not automated. For each file in the work list:

1. Download it, noting its generation. Read it with pyarrow and drop the
   person's rows. For CDC, parse `raw_value` and `raw_key` and match on `after`
   and `before`. Write it back with the same name, the same schema metadata and
   Snappy compression.
2. Check that the row count fell by exactly the number in the work list. If
   not, stop and write nothing for that file.
3. Upload it over the original with `if_generation_match` set to the
   generation you read, so a pipeline write in between is never overwritten.
4. Keep nothing on disk. The test did all of this in memory, so no local copy
   of the person exists.
5. Run queries A and B again. The count for that file is now 0.

For the test buyer, that was 6 files, rewritten in 2 seconds. A buyer from
the Step 2 snapshot means 3 to 6 more files of up to 18 MB, and the problems
below. Two things make Bronze slow:

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
| Date | 2026-11-21, by Anas ([erasure-test.json](../evidence/step10/erasure-test.json)) |
| Identifier | One `buyer_id` that appears **only** in the Step 7 scheduled extract: 1 order, 2 lines, no address, no review, no click. Chosen so the frozen Step 2 figures stay unchanged. The id itself is recorded nowhere in this repo |
| Rows found | 6 Bronze files: 3 scheduled-order loads of the same day (1 row each; that day was extracted three times), 1 scheduled order-items file (2 rows), 1 CDC orders file (1), 1 CDC order-items file (1). Warehouse 0 rows (built from the snapshot only), silver 2, gold 2. Found in 10 seconds of queries |
| Bronze rewritten | 6 objects, every one losing exactly the expected rows, new generations recorded. 2 seconds in total |
| Warehouse | nothing to do: 0 rows |
| Silver and gold | `dbt build --selector full`, 55 s: PASS 102, WARN 1 (`not_null_dim_product_p_name`, by design), ERROR 0. `fct_order_items` 208,424 → 208,422, `fct_daily_demand` 207,543 → 207,541 (two product, country and day rows that only this buyer had), the dims unchanged. `buyer_id` still tagged after the rebuild |
| Proof | Queries A and B rerun: 0 rows in every Bronze table, the CDC prefixes, the warehouse, silver and gold. Job ids are in the evidence file. Throwaway tables dropped |
| Time | About 25 minutes of work, almost all of it working out how to search the CDC files. Running the commands took about 70 seconds |
| What did not work | Query A failed on the first run (missing partition filters). Query B as first written would have matched nothing (BYTES columns, base64 in `TO_JSON_STRING`). Both fixed above |
| Not erased | The source PostgreSQL and the Kafka topic (section 6): a re-extract of 2026-09-23, or a CDC replay, would bring the buyer back. The 6 old object generations, held by GCS soft delete. The old gold tables, held by time travel and fail-safe |
| 14-day window closes | 2026-12-05: 7 days of soft delete and time travel, then 7 of fail-safe for the BigQuery tables |
