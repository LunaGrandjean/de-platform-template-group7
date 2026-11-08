# Adopt, do not recreate: every resource below already existed when Terraform
# arrived (Step 8). Each import block maps a live resource to its address; the
# plan must say "No changes" once the arguments in main.tf/iam.tf match GCP.
# Kept after the first apply as a record of what was adopted, and harmless:
# an import of an address already in state is a no-op.

locals {
  ds_iam = "projects/${var.project_id}/datasets"
}

import {
  to = google_storage_bucket.bronze
  id = "data-engineering-i1-marketplace-group"
}

import {
  to = google_bigquery_dataset.bronze
  id = "projects/${var.project_id}/datasets/g07_bronze"
}

import {
  to = google_bigquery_dataset.warehouse
  id = "projects/${var.project_id}/datasets/g07_warehouse"
}

import {
  to = google_bigquery_dataset.silver
  id = "projects/${var.project_id}/datasets/g07_silver"
}

import {
  to = google_bigquery_dataset.gold
  id = "projects/${var.project_id}/datasets/g07_gold"
}

import {
  to = google_bigquery_dataset_iam_member.bronze_owner
  id = "${local.ds_iam}/g07_bronze roles/bigquery.dataOwner ${local.bronze_owner}"
}

import {
  for_each = toset(var.dataset_readers)
  to       = google_bigquery_dataset_iam_member.bronze_readers[each.value]
  id       = "${local.ds_iam}/g07_bronze roles/bigquery.dataViewer ${each.value}"
}

import {
  to = google_bigquery_dataset_iam_member.warehouse_owner
  id = "${local.ds_iam}/g07_warehouse roles/bigquery.dataOwner ${local.bronze_owner}"
}

import {
  for_each = toset(local.warehouse_users)
  to       = google_bigquery_dataset_iam_member.warehouse_writers[each.value]
  id       = "${local.ds_iam}/g07_warehouse roles/bigquery.dataEditor ${each.value}"
}

import {
  to = google_bigquery_dataset_iam_member.silver_owner
  id = "${local.ds_iam}/g07_silver roles/bigquery.dataOwner ${local.dbt_owner}"
}

import {
  to = google_bigquery_dataset_iam_member.gold_owner
  id = "${local.ds_iam}/g07_gold roles/bigquery.dataOwner ${local.dbt_owner}"
}
