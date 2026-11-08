# ADR 0008: Keep Terraform state in a versioned GCS bucket of our own

- **Status:** accepted
- **Date:** 2026-11-08
- **Author:** Émile Gadenne, group 7, Step 8 (Terraform)
- **Lesson:** L08

## Context

Terraform's state maps each address in `infra/terraform/` to a real resource:
our Bronze bucket, four `g07_*` datasets and 12 dataset grants, 17 objects in
all ([infra.md](../infra.md)). Without it Terraform no longer knows it owns
them: the next `plan` would try to create them again and fail on name
conflicts, or, with the import blocks, re-adopt them. Facts that shape where it
lives:

- **Five people run Terraform**, from their own laptops, with their own Google
  identity. Two of them applying at once against two copies of the state is
  how resources get lost.
- **The state holds every attribute we manage**, including member emails and
  dataset settings. Ours holds no secret today (no key, no password: checked by
  grep on 2026-11-08), but any future `google_*_key` resource would put one
  there in clear text.
- **The project is shared** by every group of the course, and we cannot create
  service accounts there. We can create buckets.
- **Size:** 37,557 bytes after adoption. Storage cost is effectively zero.

## Options considered

| Option | For | Against |
|---|---|---|
| Local state (`terraform.tfstate` on one laptop) | Nothing to set up. | One person holds the only copy; others cannot plan. Easy to commit by mistake. No lock: two applies race. Lost with the laptop. |
| **GCS bucket, versioned (chosen)** | Shared by the group; native locking (a `.tflock` object) during plan/apply; every write keeps the previous version; same IAM and region as the rest of the platform; free at this size. | One bucket to create by hand and protect. Anyone with read on it reads the state. |
| Terraform Cloud (HCP) free tier | Locking, history, UI, remote runs. | Another account per member and another place where access must be managed; the state leaves GCP; the free tier's terms change without us. |

## Criteria

| Criterion | Local | GCS | Terraform Cloud |
|---|---|---|---|
| Five people can plan the same state | No | Yes | Yes |
| Locking against concurrent applies | No | Yes (native, `.tflock` object seen in the bucket) | Yes |
| Recovery from a bad write or deletion | No | Yes, object versions | Yes, state history |
| Access managed where the rest is | n/a | Yes, GCS IAM | No, separate accounts |
| Extra cost or account | None | None | One account each |

## Decision

The state lives in `gs://data-engineering-i1-g07-tfstate`, prefix `platform`,
in `europe-west1`, created by hand on 2026-11-08 with **object versioning on**,
public access prevention enforced and uniform bucket-level access. The bucket
is deliberately outside Terraform: a configuration must not manage the bucket
its own state lives in.

## Consequences

**Who can read it.** The bucket carries the shared project's default bindings:
project owners and editors can read and write it, project viewers can read it.
That is wider than the five of us: it includes course staff and possibly other
groups' members with project roles. Accepted while the state holds no secret.
The rule that keeps it acceptable: **no resource that creates a key or password
goes in this configuration.** Narrowing it to the five of us is in Step 10.

**If someone deletes the state this afternoon,** the next morning:

1. `terraform plan` fails to find state and proposes 17 imports again (the
   import blocks are still in `imports.tf`). Nothing is created or destroyed:
   the resources are untouched, only Terraform's memory of them is gone.
2. Stop: nobody runs `apply` until the state is back.
3. Restore the previous version, which versioning kept:
   `gcloud storage ls --all-versions gs://data-engineering-i1-g07-tfstate/platform/`
   then `gcloud storage cp "gs://data-engineering-i1-g07-tfstate/platform/default.tfstate#<generation>" gs://data-engineering-i1-g07-tfstate/platform/default.tfstate`.
4. `terraform plan` must say "No changes". If the whole bucket was deleted
   (versions included, beyond its 7-day soft delete), recreate it and re-adopt
   with the import blocks: about ten minutes, which is why they stay in the code.

**What we have to watch.** A stuck lock after a crashed apply
(`terraform force-unlock <id>`, only after checking nobody is applying). And
noncurrent versions pile up: a few KB each, so no lifecycle rule yet.

**What would change our mind.** A secret in state (a service account key, a
generated password): then the bucket gets its own IAM limited to the pipeline
identity and named people, or the state moves to an encrypted backend with a
customer-managed key. More than one configuration (one per environment): one
prefix each in the same bucket, still no new tool. Remote runs with an approval
UI for a larger team: Terraform Cloud becomes worth the extra accounts.
