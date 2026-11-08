# Group 7 resources in the shared course project. Every resource below existed
# before Terraform and was adopted with the import blocks in imports.tf: the
# arguments mirror what GCP returned on 2026-11-08, so the first plan is empty.

# --- Bronze bucket -----------------------------------------------------------

resource "google_storage_bucket" "bronze" {
  name          = "data-engineering-i1-marketplace-group"
  location      = "EUROPE-WEST1"
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = {
    application  = "albert-marketplace"
    layer        = "bronze"
    "managed-by" = "python"
  }

  soft_delete_policy {
    retention_duration_seconds = 604800 # 7 days, the GCS default
  }

  # Same three rules as infra/lifecycle.json (Step 2): Bronze objects cool down
  # as they age; nothing is ever deleted by lifecycle.
  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age                   = 30
      matches_prefix        = ["bronze/"]
      matches_storage_class = ["STANDARD"]
    }
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
    condition {
      age                   = 90
      matches_prefix        = ["bronze/"]
      matches_storage_class = ["STANDARD", "NEARLINE"]
    }
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
    condition {
      age                   = 365
      matches_prefix        = ["bronze/"]
      matches_storage_class = ["STANDARD", "NEARLINE", "COLDLINE"]
    }
  }

  # Bronze is the only copy of what arrived: a plan that destroys it must fail.
  lifecycle {
    prevent_destroy = true
  }
}

# --- BigQuery datasets ---------------------------------------------------------
# `access` is not declared on the datasets: it would be authoritative and would
# strip the project-level special groups. Named grants are additive members in
# iam.tf instead.

resource "google_bigquery_dataset" "bronze" {
  dataset_id            = "g07_bronze"
  location              = var.region
  description           = "Group 7: external tables over the Bronze Parquet snapshot in GCS"
  max_time_travel_hours = "168"

  labels = {
    group = "g07"
    layer = "bronze"
    step  = "l04"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_bigquery_dataset" "warehouse" {
  dataset_id            = "g07_warehouse"
  location              = var.region
  description           = "Group 7: native typed working tables loaded from Bronze (Step 4)"
  max_time_travel_hours = "168"

  labels = {
    group = "g07"
    layer = "warehouse"
    step  = "l04"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Silver and gold were created by `dbt build` (Step 5) with no description and
# no labels. Adopted as they are; labels come in Step 9.
resource "google_bigquery_dataset" "silver" {
  dataset_id            = "g07_silver"
  location              = var.region
  max_time_travel_hours = "168"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_bigquery_dataset" "gold" {
  dataset_id            = "g07_gold"
  location              = var.region
  max_time_travel_hours = "168"

  lifecycle {
    prevent_destroy = true
  }
}
