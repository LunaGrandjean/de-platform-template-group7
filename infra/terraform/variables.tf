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

variable "import_service_account" {
  description = <<-EOT
    Set to true (with create_service_account = true) only if the course admin
    created g07-pipeline for us: Terraform then imports the existing account
    instead of creating it again, which would fail with 409. Leave false if the
    admin grants us iam.serviceAccounts.create and Terraform creates it.
  EOT
  type        = bool
  default     = false
}

variable "env" {
  description = "Label `env` on every resource. One environment today; the key exists so a future prod is never read as dev."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env is dev or prod."
  }
}

variable "billing_account_id" {
  description = <<-EOT
    Billing account behind data-engineering-i1, as XXXXXX-XXXXXX-XXXXXX. Empty
    means the budget and its notification channel are declared but not created:
    the Cloud Billing API is disabled in the shared project and our identities
    cannot read the account (checked 2026-11-19, docs/costs.md). The course admin
    supplies it, or creates the budget from this definition.
  EOT
  type        = string
  default     = ""
}

variable "project_number" {
  description = "Numeric id of data-engineering-i1, needed by the budget filter. Only read when billing_account_id is set."
  type        = string
  default     = ""
}

variable "budget_amount" {
  description = "Monthly budget for spend labelled group=g07, in the billing account's currency."
  type        = number
  default     = 10
}

variable "budget_alert_email" {
  description = "The one person the budget alert reaches. A person who can act, never a shared inbox."
  type        = string
  default     = "amohamed@albertschool.com"
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
