# Step 9: a budget on group 7's share of the shared project, and the person it
# reaches. It DOES NOT STOP anything: it sends an email at 50%, 90% and 100% of
# the amount, then nothing more. No query is refused and nothing is switched off.
# The only thing that refuses spend is the per-query cap (maximum_bytes_billed,
# 1 GB in dbt and the Step 4 script) and project quotas.
#
# Scoped by label, not by project: data-engineering-i1 is shared by every group,
# so a project-wide budget would fire on other groups' spend. The filter only
# sees lines labelled group=g07, which means only spend from 2026-11-19 on, and
# only from resources and jobs that carry the label (docs/costs.md).
#
# Declared but NOT created while billing_account_id is empty: the Cloud Billing
# API is disabled in the project and our identities cannot read the billing
# account (403 SERVICE_DISABLED, 2026-11-19). The course admin either passes the
# account id, or creates the same budget by hand from this definition. Until
# then, the course's own project budget is the only alarm, and it reaches the
# admin, not us.

locals {
  create_budget = var.billing_account_id != ""
}

resource "google_monitoring_notification_channel" "budget_owner" {
  count        = local.create_budget ? 1 : 0
  display_name = "g07 budget owner"
  type         = "email"

  labels = {
    email_address = var.budget_alert_email
  }

  user_labels = {
    layer     = "finops"
    component = "terraform"
  }
}

resource "google_billing_budget" "g07" {
  count           = local.create_budget ? 1 : 0
  billing_account = var.billing_account_id
  display_name    = "g07 monthly (label group=g07)"

  budget_filter {
    projects               = ["projects/${var.project_number}"]
    labels                 = { group = "g07" }
    calendar_period        = "MONTH"
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      units = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }
  # Forecast: warns before the money is spent, not after.
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.budget_owner[0].id]
    # Our channel only: the billing account's admins are other people's inbox.
    disable_default_iam_recipients = true
  }
}
