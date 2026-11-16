{#
  Step 7: (re)creates g07_bronze.scheduled_orders, the external table over the scheduler's
  interval extracts in bronze/scheduled/orders/interval_date=D/load_id=L/.
  Run by the DAG before dbt: dbt run-operation create_scheduled_orders_table
  CREATE OR REPLACE makes it safe to run on every DAG run; it reads no data.
  Bronze holds every load; stg_scheduled_orders keeps only the newest one per day.
  No labels option: BigQuery rejects it in CREATE EXTERNAL TABLE ("Unknown option:
  labels"), found on the first scheduled run.
#}
{% macro create_scheduled_orders_table() %}
  {% set bucket = var('bronze_bucket', 'data-engineering-i1-marketplace-group') %}
  {% set prefix = 'gs://' ~ bucket ~ '/bronze/scheduled/orders' %}
  {% set sql %}
    create or replace external table `{{ target.project }}.g07_bronze.scheduled_orders`
    with partition columns (interval_date date, load_id string)
    options (
      format = 'PARQUET',
      uris = ['{{ prefix }}/*'],
      hive_partition_uri_prefix = '{{ prefix }}',
      require_hive_partition_filter = true
    )
  {% endset %}
  {% do run_query(sql) %}
  {% do log('g07_bronze.scheduled_orders points at ' ~ prefix, info=true) %}
{% endmacro %}
