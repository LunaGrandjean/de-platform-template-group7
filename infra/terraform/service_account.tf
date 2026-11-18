# The pipeline's identity: Airflow (Step 7) should run the ingestion and dbt
# images as this account instead of as a person. Today the DAG mounts the
# operator's own Google credentials (volume g07_gcloud, docs/orchestration.md);
# switching to this account changes that volume only, not the DAG.
#
# Declared but NOT created: in the shared course project our accounts lack
# iam.serviceAccounts.create (testIamPermissions, 2026-11-08). Set
# create_service_account = true once the course admin grants it.
# No key is ever created for it: workloads use impersonation or the runtime's
# attached identity, so no credential file can leak.
#
# The grants match what the three DAG tasks do:
#   extract_orders       writes bronze/scheduled/... objects        -> objectUser on the bucket
#   create_bronze_table  CREATE OR REPLACE EXTERNAL TABLE           -> dataEditor on g07_bronze
#                        g07_bronze.scheduled_orders / _order_items
#   dbt_build            reads g07_bronze and g07_warehouse,        -> dataEditor on g07_silver
#                        writes views in g07_silver and              and g07_gold
#                        tables in g07_gold
# dataEditor on g07_warehouse covers the Step 4 loads once they are scheduled.
# Running any query also needs roles/bigquery.jobUser, which only exists at
# project level. This configuration never touches the shared project's IAM, so
# that one grant is asked of the course admin together with the account
# (docs/infra.md).

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

# Reads every dataset it builds from and (re)creates what it owns. On g07_bronze
# that is only the two scheduled external tables: their data stays in GCS,
# where lifecycle never deletes.
resource "google_bigquery_dataset_iam_member" "pipeline_write" {
  for_each = var.create_service_account ? {
    bronze    = google_bigquery_dataset.bronze.dataset_id
    warehouse = google_bigquery_dataset.warehouse.dataset_id
    silver    = google_bigquery_dataset.silver.dataset_id
    gold      = google_bigquery_dataset.gold.dataset_id
  } : {}
  dataset_id = each.value
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pipeline[0].email}"
}
