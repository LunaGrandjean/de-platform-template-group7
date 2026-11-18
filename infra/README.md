# Infrastructure

Since Step 8, group 7's cloud resources (the Bronze bucket, the four `g07_*`
datasets and their named grants) are declared in [`terraform/`](terraform/) and
changed through code, not the console. How to run it, what each resource is
for, what stays outside Terraform and the drift rules:
[`docs/infra.md`](../docs/infra.md). Where the state lives:
[ADR 0008](../docs/adr/0008-remote-state.md).

| Path | What it is |
|---|---|
| [`terraform/`](terraform/) | The configuration: Terraform 1.17.1, Google provider 8.9.0, remote state in GCS |
| [`lifecycle.json`](lifecycle.json) | The Step 2 Bronze lifecycle rules; the same three rules are now in `terraform/main.tf` |
| [`iam.md`](iam.md) | The Step 2 bucket IAM as observed on 2026-10-26, before Terraform |

CI checks every change to `terraform/` with `fmt -check`, `init -backend=false`
and `validate`, with no cloud credential. `plan` and `apply` stay manual and
authenticated (see `docs/infra.md`).

Next: **Step 9** adds labels and a budget; **Step 10** tightens access, once the
pipeline runs as its own service account.
