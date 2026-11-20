# ADR 0009: Attribute spend by labels on every resource and every job, in the shared project

- **Status:** proposed
- **Date:** 2026-11-19
- **Author:** Anas Mossad, group 7, Step 9 (FinOps)
- **Lesson:** L09

## Context

Somebody asks what group 7's pipeline costs. Before this step the honest answer
was "we can guess": nothing on a bill said which lines were ours. Facts that
shape how attribution can work here:

- **One project, many payers.** Every group of the course and several
  individuals share `data-engineering-i1`: 77 datasets, 26 people running
  queries this month, 115 GiB of queries since 2026-11-01. Our share, by
  inference, is 25.1 GiB, about 22% ([costs.md](../costs.md), section 3).
- **We cannot create projects, read the billing account or create budgets.**
  The Cloud Billing API is disabled for us (403, 2026-11-19), and in Step 8 we
  could not even create a service account.
- **Our largest cost is queries, not storage** (section 4 of costs.md): BigQuery
  Analysis is about 40 times everything we store. A query is billed to the
  **job** that ran it, so it carries the job's labels, not the dataset's.
- **Our platform is declared** (Step 8), so a labelling convention is one
  `default_labels` block and one `apply`, not twenty console edits.
- **No billing export exists.** Today the only per-job source is
  `INFORMATION_SCHEMA.JOBS`, which records job labels too.

## Options considered

| Option | Buys you | Costs you |
|---|---|---|
| **Labels on every resource and every job, one project (ours)** | One project and one bill; attribution by query, both in `INFORMATION_SCHEMA.JOBS` today and in a billing export once one exists. Nothing to ask of the admin. | Labels apply forward only, so all spend before 2026-11-19 stays unattributed. Nothing enforces them: a console query or a hand-made resource simply has none. |
| A project per team | Attribution for free (the project is the label) and a hard boundary: one team cannot read, break or pay for another's resources. | A project to provision per team, which needs the admin; cross-team data (one group reading another's gold) becomes cross-project grants; the course's shared free tier and datasets get split. |
| Tags instead of labels | Inheritance from folder or organisation, and they can be **required** by organisation policy, so an untagged resource can be refused at creation. | Organisation-level setup we do not have. And tags do not reach a query job, so they would still miss our largest line. |
| Split the bill by hand | Nothing to set up. | Somebody's afternoon every month, done by grouping on user email and dataset name, and always wrong at the edges: a shared view, a member's exploratory query, a dataset without our prefix. It is what section 3 of costs.md had to do for everything before 2026-11-19. |

## Criteria

- **Can we do it ourselves, now?** Only labels and the manual split pass. A
  project per team and tags need permissions we do not have.
- **Does it attribute the largest line?** Only job labels do. Labels on
  datasets, tags and the manual split by dataset name all describe where the
  bytes were read, not who ran the job.
- **Does it survive a fourth person joining?** Labels in Terraform
  `default_labels` and in `dbt_project.yml` are applied by the code, not by
  memory. The manual split relies on the person who knows the prefixes.
- **Does it enforce itself?** None of the options we can deploy does. That is
  the weakness of the decision, recorded below.

## Decision

Attribute spend with a four-key label convention (`group`, `env`, `layer`,
`component`, defined in [costs.md](../costs.md), section 1) on every resource
Terraform declares and, just as importantly, on every BigQuery job our code
runs (dbt through `query-comment`, `scripts/warehouse.py` through its client).
The budget is scoped by the `group=g07` label inside the shared project.

## Consequences

- **Easier:** "what does the pipeline cost?" is one `GROUP BY` on the `group`
  label. A build's cost splits into models and tests (the `resource` label),
  which is how the Step 9 saving was found.
- **Harder, or not solved:** spend before 2026-11-19 is unattributable forever.
  Console and notebook queries carry no labels. A resource created by hand
  carries none until someone adopts it into Terraform. The weekly
  `plan -refresh-only` (Step 8) shows hand-made labels, not missing ones.
- **To watch:** the share of `g07_*` jobs with no `group` label, from
  `INFORMATION_SCHEMA.JOBS`. If it grows, people are working outside the code.

**With ten teams the answer would not be "more labels".** It would be a project
per team (or per team and environment) under one folder, created by the admin
from a Terraform module. The project then carries attribution and access
boundaries for free, and tags with an organisation policy refuse untagged
resources. Labels would stay, but only for what a project cannot express: the
layer and the component *inside* a team's project. Ten teams sharing one
project on the honour system of a label convention is the arrangement this
course runs on, and it works because the bill is zero. It would not survive the
first real invoice.
