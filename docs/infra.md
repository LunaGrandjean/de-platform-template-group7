# Infrastructure as code (Step 8)

Group 7's cloud resources are declared in [`infra/terraform/`](../infra/terraform/)
and changed only through it. The course project `data-engineering-i1` is shared
by every group, so Terraform manages **only our resources** (the `g07_*`
datasets and our Bronze bucket) and never anything at project level.

Every claim below has a transcript in [`evidence/step8/`](evidence/step8/).

## How to run it

Prerequisites: Terraform 1.17.x and your own Google identity
(`gcloud auth application-default login`). Nobody shares a key; there is none.

```bash
cd infra/terraform
terraform init      # downloads google 8.9.0, checks it against .terraform.lock.hcl, connects the GCS state
terraform plan      # must say "No changes" on main
terraform plan -refresh-only   # weekly: shows changes Terraform does not manage (see Drift)
```

Every PR touching `infra/terraform/` runs `fmt -check`, `init -backend=false`
and `validate` in [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml).
That check needs no credential. `plan` and `apply` stay manual and
authenticated: the author pastes the plan output in the PR description, and
`apply` runs after review, from `main`.

## Resources: one line each, and why it exists

| Address | Real resource | Why it exists |
|---|---|---|
| `google_storage_bucket.bronze` | `gs://data-engineering-i1-marketplace-group` | The Bronze lake: the only copy of what arrived from PostgreSQL, Debezium and Kafka (Steps 2-3). `prevent_destroy`; its lifecycle cools objects to Nearline/Coldline/Archive and never deletes. |
| `google_bigquery_dataset.bronze` | `g07_bronze` | External tables over the Bronze Parquet, so SQL and dbt read the lake without loading it (Step 4). |
| `google_bigquery_dataset.warehouse` | `g07_warehouse` | Native month-partitioned orders and order lines plus the daily-demand MV, for queries filtered often (Step 4, ADR 0004). |
| `google_bigquery_dataset.silver` | `g07_silver` | dbt staging and intermediate views: typed, deduplicated records (Step 5, ADR 0005). |
| `google_bigquery_dataset.gold` | `g07_gold` | dbt marts: the daily-demand star read by the ML team and reports (Step 5). |
| `google_bigquery_dataset_iam_member.bronze_owner` | Émile, `dataOwner` on `g07_bronze` | Created the dataset; can grant access. |
| `google_bigquery_dataset_iam_member.bronze_readers[*]` (4) | Anas, Luna, Malek, Omar, `dataViewer` on `g07_bronze` | Every member reads Bronze to build and debug Silver. Read only: Bronze is never edited by hand. |
| `google_bigquery_dataset_iam_member.warehouse_owner` | Émile, `dataOwner` on `g07_warehouse` | Created the dataset; can grant access. |
| `google_bigquery_dataset_iam_member.warehouse_writers[*]` (4) | Anas, Luna, Malek, Omar, `dataEditor` on `g07_warehouse` | Every member ran Step 4 loads and tuning experiments. |
| `google_bigquery_dataset_iam_member.silver_owner` | Malek, `dataOwner` on `g07_silver` | First `dbt build` created the dataset under his identity. |
| `google_bigquery_dataset_iam_member.gold_owner` | Malek, `dataOwner` on `g07_gold` | Same. |
| `google_service_account.pipeline` + 3 bindings | `g07-pipeline@…` (**not created**, `count = 0`) | The identity Airflow (Step 7) should run the images as, instead of a person. Our accounts lack `iam.serviceAccounts.create` in the shared project (`testIamPermissions`, 2026-11-08). Created once the course admin grants it: set `create_service_account = true`. |

**Outside Terraform, on purpose:**

| Resource | Why not in Terraform |
|---|---|
| `gs://data-engineering-i1-g07-tfstate` | Holds the state itself; created by hand on 2026-11-08 (versioning on, public access prevention enforced, uniform access). A configuration cannot safely manage the bucket its own state lives in. |
| Project default bindings (`projectOwners/Writers/Readers` on the datasets, `projectEditor/Viewer` on the bucket) | Inherited from the shared project, owned by the course admin. Declaring them in our state would let our `apply` change other groups' access. They are broader than our matrix needs: gap kept for Step 10. |
| The project, APIs, billing | Owned by the course admin. |

## Adoption: import, not recreate

All 17 resources already existed. [`imports.tf`](../infra/terraform/imports.tf)
maps each to its address. On 2026-11-08:

1. First plan: `Plan: 17 to import, 0 to add, 3 to change, 0 to destroy.`
   ([01](evidence/step8/01-plan-adopt.txt)). The 3 changes were the labels of
   the bucket, `g07_bronze` and `g07_warehouse`: the Google provider (v5+)
   does not copy labels into state on import, so it plans to write labels that
   are already there with the same values.
2. Apply of that saved plan: `17 imported, 0 added, 3 changed, 0 destroyed`
   ([02](evidence/step8/02-apply-adopt.txt)).
3. Next plan: **"No changes. Your infrastructure matches the configuration."**
   ([03](evidence/step8/03-plan-after-adopt.txt)).

The state is `gs://data-engineering-i1-g07-tfstate/platform/default.tfstate`
(17 resources, about 37 KB). Every apply leaves the previous version as a
noncurrent object; GCS locks it during plan/apply.

## Drift: provoked and detected

Two out-of-band changes on 2026-11-08, through the BigQuery API rather than
Terraform, to see what `plan` actually catches.

| # | Change made by hand | Plain `plan` | Decision | Result |
|---|---|---|---|---|
| 1 | Added label `drift=test` to `g07_silver` ([04](evidence/step8/04-drift-provoked.txt)) | **Not detected**: "No changes", exit 0 ([05](evidence/step8/05-plan-drift-detected.txt)) | Overwrite (an unwanted label). Terraform cannot remove a label it does not manage, so removed by API ([10](evidence/step8/10-cleanup-silver.txt)). | Gone |
| 2 | Changed managed label `step` from `l04` to `hotfix` on `g07_bronze`, as a console hotfix would ([07](evidence/step8/07-drift-managed.txt)) | **Detected**: exit 2, `"hotfix" -> "l04"`, `1 to change` ([08](evidence/step8/08-plan-drift-managed.txt)) | Overwrite: the hotfix was never agreed. | `0 added, 1 changed, 0 destroyed` ([09](evidence/step8/09-apply-overwrite-drift.txt)) |

Drift 1 only appeared with `terraform plan -refresh-only`: "Objects have
changed outside of Terraform … `effective_labels` + "drift" = "test""
([06](evidence/step8/06-plan-refresh-only.txt)). After the cleanup both plans
say "No changes" ([11](evidence/step8/11-plan-final.txt),
[13](evidence/step8/13-apply-refresh-only.txt): the refresh-only apply only
rewrote state, no remote object).

**What we learned:** a plain plan only compares the attributes we declared. A
label, a grant or a setting added by hand outside the code is invisible to it.
So `plan -refresh-only` runs weekly, and its output is read, not just its exit
code. The same blind spot applies to dataset `access` entries, which we left
undeclared (see [`main.tf`](../infra/terraform/main.tf)).

**Adopt or overwrite, the rule:** overwrite by default (`apply` restores the
code). Adopt when the hand change was right: put the same value in the code,
open a PR, and the next plan says "No changes" without touching the resource.

**In an emergency** (a grant needed at 23:00 for a broken pipeline): make the
fix in the console, then **within the same day** open a PR that adds it to the
code, and post in the group chat that `main` is drifted until it merges.
Until then nobody runs `apply`, because it would silently revert the fix.

## Not covered yet

- The service account exists only in code (see above).
- `plan` does not run in CI: that needs a GCP identity for GitHub (Workload
  Identity Federation), which needs the same admin permission as the service
  account.
- Labels on Silver and Gold, and a budget alert: Step 9.
- Removing the broad project default bindings: Step 10.
