# Step 10: column classification, enforced (docs/governance.md, ADR 0010).
#
# A taxonomy holds our classes; a policy tag is one class. A column carrying a
# tag is unreadable to everybody, project owners included, except the holders of
# roles/datacatalog.categoryFineGrainedReader on that tag. That is the point in a
# shared project: every g07 dataset also grants projectReaders/projectWriters,
# so dataset IAM alone lets the whole course read our data.
#
# What tags the columns is not here. Terraform owns the classes and who may read
# them; the tables own their schemas:
#   - g07_gold.fct_order_items.buyer_id: transform/models/marts/marts.yml (dbt
#     re-applies it on every build, persist_docs columns)
#   - g07_warehouse.orders.buyer_id: scripts/warehouse.py, after each rebuild
# Bronze is external tables over GCS; BigQuery refuses policy tags on them
# without a BigLake connection, which we cannot create (docs/governance.md, gaps).
#
# PRIVILEGED: whoever holds roles/datacatalog.categoryAdmin on this taxonomy can
# delete it, and every tagged column becomes readable again while its schema
# still shows the tag. Nobody in the group is granted it here.
#
# Taxonomies take no labels. Spend on Data Catalog policy tags is zero.

resource "google_data_catalog_taxonomy" "g07" {
  region       = var.region
  display_name = "g07-marketplace-classification"
  description  = "Group 7 column classes (Step 10). Shared project: prefixed g07. Owner: group 7, docs/governance.md."
  # Without FINE_GRAINED_ACCESS_CONTROL the taxonomy is created and enforces nothing.
  activated_policy_types = ["FINE_GRAINED_ACCESS_CONTROL"]
}

# Named for what the data is, never for who may see it: the audience changes.
resource "google_data_catalog_policy_tag" "pii_identifier" {
  taxonomy     = google_data_catalog_taxonomy.g07.id
  display_name = "pii-identifier"
  description  = "A key that points at one person (buyer_id, customer_id, session_id). Pseudonymous, still personal data under GDPR."
}

resource "google_data_catalog_policy_tag" "pii_contact" {
  taxonomy     = google_data_catalog_taxonomy.g07.id
  display_name = "pii-contact"
  description  = "Directly identifying contact data (street address, phone). Lives only in Bronze today, where it cannot be enforced."
}

# The access matrix, row "engineer": the five members read both classes.
# Nobody else does: not the analyst role, not the pipeline service account,
# not the project owners.
resource "google_data_catalog_policy_tag_iam_member" "identifier_readers" {
  for_each   = toset(var.pii_readers)
  policy_tag = google_data_catalog_policy_tag.pii_identifier.name
  role       = "roles/datacatalog.categoryFineGrainedReader"
  member     = each.value
}

resource "google_data_catalog_policy_tag_iam_member" "contact_readers" {
  for_each   = toset(var.pii_readers)
  policy_tag = google_data_catalog_policy_tag.pii_contact.name
  role       = "roles/datacatalog.categoryFineGrainedReader"
  member     = each.value
}

output "policy_tag_pii_identifier" {
  description = "Resource name dbt (vars.g07_pii_identifier_tag) and scripts/warehouse.py tag columns with."
  value       = google_data_catalog_policy_tag.pii_identifier.name
}

output "policy_tag_pii_contact" {
  description = "Resource name of the pii-contact tag."
  value       = google_data_catalog_policy_tag.pii_contact.name
}
