# The pipeline's identity: Airflow (Step 7) runs the ingestion and dbt images
# as this account instead of as a person.
#
# Declared but NOT created: in the shared course project our accounts lack
# iam.serviceAccounts.create (testIamPermissions, 2026-11-08). Set
# create_service_account = true once the course admin grants it.
# No key is ever created for it: workloads use impersonation or the runtime's
# attached identity, so no credential file can leak.

resource "google_service_account" "pipeline" {
  count        = var.create_service_account ? 1 : 0
  account_id   = "g07-pipeline"
  display_name = "Group 7 pipeline (ingestion + dbt)"
  description  = "Runs the g07 ingestion and dbt containers. Managed by Terraform in infra/terraform."
}

# Writes new Bronze objects (and reads them back), cannot change bucket policy.
resource "google_storage_bucket_iam_member" "pipeline_bronze" {
  count  = var.create_service_account ? 1 : 0
  bucket = google_storage_bucket.bronze.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.pipeline[0].email}"
}

# Reads Bronze tables, writes warehouse, silver and gold.
resource "google_bigquery_dataset_iam_member" "pipeline_bronze_read" {
  count      = var.create_service_account ? 1 : 0
  dataset_id = google_bigquery_dataset.bronze.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.pipeline[0].email}"
}

resource "google_bigquery_dataset_iam_member" "pipeline_write" {
  for_each = var.create_service_account ? {
    warehouse = google_bigquery_dataset.warehouse.dataset_id
    silver    = google_bigquery_dataset.silver.dataset_id
    gold      = google_bigquery_dataset.gold.dataset_id
  } : {}
  dataset_id = each.value
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pipeline[0].email}"
}
