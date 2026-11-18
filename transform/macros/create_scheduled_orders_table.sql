{#
  Step 7: (re)creates the two external tables over the scheduler's interval extracts:
    g07_bronze.scheduled_orders       bronze/scheduled/orders/interval_date=D/load_id=L/
    g07_bronze.scheduled_order_items  bronze/scheduled/order_items/interval_date=D/load_id=L/
  Run by the DAG before dbt: dbt run-operation create_scheduled_orders_table
  (the name predates the order lines and is kept so the DAG task stays the same).
  CREATE OR REPLACE makes it safe to run on every DAG run; it reads no data.
  Bronze holds every load; silver keeps only the newest orders load per day and the
  lines of that same load.
  No labels option: BigQuery rejects it in CREATE EXTERNAL TABLE ("Unknown option:
  labels"), found on the first scheduled run.
#}
{% macro create_scheduled_orders_table() %}
  {% set bucket = var('bronze_bucket', 'data-engineering-i1-marketplace-group') %}
  {% for table, folder in [('scheduled_orders', 'orders'), ('scheduled_order_items', 'order_items')] %}
    {% set prefix = 'gs://' ~ bucket ~ '/bronze/scheduled/' ~ folder %}
    {% set sql %}
      create or replace external table `{{ target.project }}.g07_bronze.{{ table }}`
      with partition columns (interval_date date, load_id string)
      options (
        format = 'PARQUET',
        uris = ['{{ prefix }}/*'],
        hive_partition_uri_prefix = '{{ prefix }}',
        require_hive_partition_filter = true
      )
    {% endset %}
    {% do run_query(sql) %}
    {% do log('g07_bronze.' ~ table ~ ' points at ' ~ prefix, info=true) %}
  {% endfor %}
{% endmacro %}
