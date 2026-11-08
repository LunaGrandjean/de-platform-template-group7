# Access is granted per resource (bucket or dataset), never at project level.
# These are additive *_iam_member resources: they add one principal to one role
# and leave the project's default bindings (projectOwners/Writers/Readers,
# projectEditor/Viewer on the bucket) in place. Those defaults are outside
# Terraform; docs/infra.md lists them as a known gap, tightened in Step 10.

locals {
  bronze_owner    = "user:egadenne@albertschool.com"
  dbt_owner       = "user:msaoudi@albertschool.com"
  warehouse_users = var.dataset_readers
}

# g07_bronze: Émile owns it, the four other members read it.
resource "google_bigquery_dataset_iam_member" "bronze_owner" {
  dataset_id = google_bigquery_dataset.bronze.dataset_id
  role       = "roles/bigquery.dataOwner"
  member     = local.bronze_owner
}

resource "google_bigquery_dataset_iam_member" "bronze_readers" {
  for_each   = toset(var.dataset_readers)
  dataset_id = google_bigquery_dataset.bronze.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = each.value
}

# g07_warehouse: Émile owns it, every member writes it (Step 4 loads).
resource "google_bigquery_dataset_iam_member" "warehouse_owner" {
  dataset_id = google_bigquery_dataset.warehouse.dataset_id
  role       = "roles/bigquery.dataOwner"
  member     = local.bronze_owner
}

resource "google_bigquery_dataset_iam_member" "warehouse_writers" {
  for_each   = toset(local.warehouse_users)
  dataset_id = google_bigquery_dataset.warehouse.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = each.value
}

# g07_silver and g07_gold: owned by whoever first ran `dbt build` (Malek).
resource "google_bigquery_dataset_iam_member" "silver_owner" {
  dataset_id = google_bigquery_dataset.silver.dataset_id
  role       = "roles/bigquery.dataOwner"
  member     = local.dbt_owner
}

resource "google_bigquery_dataset_iam_member" "gold_owner" {
  dataset_id = google_bigquery_dataset.gold.dataset_id
  role       = "roles/bigquery.dataOwner"
  member     = local.dbt_owner
}
