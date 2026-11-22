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

# Step 10, the narrowed grant: warehouse_writers (dataEditor, already in state
# since the Step 8 apply) is renamed warehouse_readers, which says dataViewer.
# role forces replacement, so the plan shows -/+ for each member: the dataEditor
# binding destroyed, a dataViewer one created. That replace IS the narrowing, in
# one apply, with nothing done by hand.
moved {
  from = google_bigquery_dataset_iam_member.warehouse_writers
  to   = google_bigquery_dataset_iam_member.warehouse_readers
}

import {
  to = google_bigquery_dataset_iam_member.silver_owner
  id = "${local.ds_iam}/g07_silver roles/bigquery.dataOwner ${local.dbt_owner}"
}

import {
  to = google_bigquery_dataset_iam_member.gold_owner
  id = "${local.ds_iam}/g07_gold roles/bigquery.dataOwner ${local.dbt_owner}"
}

# Only when the course admin creates g07-pipeline for us (docs/infra.md,
# "The pipeline's identity"): adopt it instead of creating it again.
# Empty set by default, so this block plans nothing.
import {
  for_each = var.create_service_account && var.import_service_account ? toset(["g07-pipeline"]) : toset([])
  to       = google_service_account.pipeline[0]
  id       = "projects/${var.project_id}/serviceAccounts/${each.value}@${var.project_id}.iam.gserviceaccount.com"
}

# Step 10: the taxonomy and its two tags were created through the API on
# 2026-11-20 (docs/evidence/step10/taxonomy-created.json), because apply needs
# Terraform 1.17. The next apply adopts them instead of creating duplicates.
import {
  to = google_data_catalog_taxonomy.g07
  id = "projects/${var.project_id}/locations/${var.region}/taxonomies/839634828442859651"
}

import {
  to = google_data_catalog_policy_tag.pii_identifier
  id = "projects/${var.project_id}/locations/${var.region}/taxonomies/839634828442859651/policyTags/2241334323157841260"
}

import {
  to = google_data_catalog_policy_tag.pii_contact
  id = "projects/${var.project_id}/locations/${var.region}/taxonomies/839634828442859651/policyTags/1875540059977754680"
}
