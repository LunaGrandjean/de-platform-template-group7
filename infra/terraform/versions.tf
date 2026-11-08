# Terraform and provider versions are pinned exactly: the same code must give
# the same plan on every laptop and in CI. `.terraform.lock.hcl` is committed
# and holds the provider checksums.
terraform {
  required_version = "~> 1.17.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 8.9.0"
    }
  }

  # Remote state in a versioned GCS bucket, created by hand on 2026-11-08
  # (see docs/infra.md): Terraform cannot store its state in a bucket it manages.
  # GCS locks the state natively during plan/apply.
  backend "gcs" {
    bucket = "data-engineering-i1-g07-tfstate"
    prefix = "platform"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
