# Step 9: the label convention, in one place. Why each key exists, and what is
# already unattributable, is in docs/costs.md ("Label convention").
#
#   group      who pays: g07. The project is shared by every group of the course,
#              so without it our lines cannot be told apart from theirs.
#   env        dev or prod, so a test spike is never read as production.
#   layer      bronze, warehouse, silver, gold, tfstate: which medallion layer the
#              cost belongs to. Each layer has a different cost driver.
#   component  the code that writes into the resource or runs the job:
#              ingestion, warehouse, dbt, terraform. The person to ask.
#
# Values: lowercase letters, digits, "_" and "-", at most 63 characters (GCP).
# Labels only apply from the moment they are set: they never relabel past
# billing lines.

locals {
  default_labels = {
    group = "g07"
    env   = var.env
  }
}
