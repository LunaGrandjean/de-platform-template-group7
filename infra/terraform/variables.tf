variable "project_id" {
  description = "Course GCP project, shared by every group (our resources are prefixed g07)."
  type        = string
  default     = "data-engineering-i1"
}

variable "region" {
  description = "Every group-7 resource lives in europe-west1."
  type        = string
  default     = "europe-west1"
}

variable "create_service_account" {
  description = <<-EOT
    Our identities cannot create service accounts in the shared project
    (iam.serviceAccounts.create denied, checked 2026-11-08). The service account
    is declared but only created when this is true, once the course admin grants
    the permission or creates it for us.
  EOT
  type        = bool
  default     = false
}

variable "dataset_readers" {
  description = "Group members with read access to g07_bronze."
  type        = list(string)
  default = [
    "user:amohamed@albertschool.com",
    "user:lgrandjean@albertschool.com",
    "user:msaoudi@albertschool.com",
    "user:oabdellatif@albertschool.com",
  ]
}
