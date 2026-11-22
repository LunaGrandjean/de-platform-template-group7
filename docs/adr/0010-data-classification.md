# ADR 0010: Grant access to personal columns by their classification, not by table, view or dataset

- **Status:** proposed
- **Date:** 2026-11-20
- **Author:** Anas Mossad, group 7, Step 10 (governance)
- **Lesson:** L10

## Context

[governance.md](../governance.md) says which of our 196 columns are personal:
22 are `pii.identifier` or `pii.contact`, 13 more are address parts, and 7 are
free text nobody has checked. This ADR decides how access to them is granted.
These facts shape the decision:

- **Dataset access is already wide open.**
  - Every `g07_*` dataset grants `projectReaders` and `projectWriters`, so
    the whole course can read our data. The bucket gives `projectViewer`
    object read.
  - We cannot remove those bindings, because they are the admin's.
  - Any control that works by narrowing *who opens the dataset* is therefore
    out of our hands.
- **Personal columns sit inside tables that everyone needs.**
  - `buyer_id` is one column of `fct_order_items`. The other nine columns
    feed every demand question.
  - Hiding the table to hide the column hides the answers too.
- **The pipeline does not read the personal columns back.**
  - `fct_daily_demand` and the tests count rows; checked in governance.md,
    section 4.
  - So restricting the column costs the pipeline nothing.
- **What we found when we tried** (governance.md, section 5):
  - Plain external tables refuse policy tags, so Bronze cannot be protected
    this way.
  - Views cannot carry tags.
  - And every student holds fine-grained read at project level, so a tag
    protects nothing *against the course* until the admin narrows that.

## Options considered

| Option | Buys you | Costs you |
|---|---|---|
| **Classify columns, grant on the class (ours)** | One rule per class that every new table inherits as soon as its column is tagged. Who may read `pii.identifier` is one IAM policy, auditable in one place. Refusals name the tag, so a refused person knows what to ask for | Two grants to reason about (the dataset, then the tag). A tag that silently protects nothing if misconfigured: deleted taxonomy, a project-wide reader, or a `CREATE OR REPLACE` that drops it. Works only on native tables |
| A view per consumer | Exactly the shape each consumer needs, no tagging, and it works over external tables | One view to write and keep in step per consumer, forever. Every view must be *authorised* on the source dataset, and the source must not be readable directly, which is exactly what we cannot remove here (`projectReaders`) |
| A dataset per sensitivity level | Simple, coarse, hard to get wrong: `g07_gold_pii` is restricted, `g07_gold` is not | The data copied twice and kept in step: `fct_order_items` with and without `buyer_id`, rebuilt together. Same `projectReaders` problem on the restricted dataset, so in this project it buys nothing until the admin acts |
| Trust people not to query it | Nothing to build | It is not a control. `INFORMATION_SCHEMA.JOBS` would eventually show the query that should not have run, after the fact |

## Criteria

- **Does it hold against access we cannot remove?** Only the tag does. A tag
  refuses a project owner, and `projectReaders` along with them. Views and
  datasets are both bypassed by reading the source dataset, which the whole
  course can do.
- **Does it survive a new table?** Classification does, once the column is
  tagged (one line in a dbt `.yml`). A view or a split dataset is new work for
  every table, and someone forgets.
- **Can we tell whether it works?** Partly. A tag's readers are one policy,
  but the only proof is a refusal. A schema that shows the tag proves nothing,
  as the deleted-taxonomy case shows. Views and split datasets can be checked
  by reading their grants, which is easier, and that is a real point in their
  favour.
- **Does it cover where our personal data is?** No option covers Bronze
  without the admin. Tags need BigLake, and views or split datasets need
  `projectReaders` removed. The real fix for Bronze is not landing the contact
  columns at all.

## Decision

Grant access to personal columns by **classification**: one taxonomy, one tag
per class, readers bound on the tag (`infra/terraform/governance.tf`). Columns
are tagged where the table is built: dbt `policy_tags` for gold,
`scripts/warehouse.py` for the warehouse. A table stays readable to everyone
with dataset access, minus its personal columns.

We chose it **despite** having been unable to prove a refusal, because it is
the only option of the four that would work once the admin narrows the
project-wide grants. The other three would still be bypassed by the source
dataset.

## Consequences

- **Easier:**
  - "Who can read buyer IDs?" is one IAM policy on one tag.
  - A new gold table with a buyer key is protected by one line of YAML.
  - A refused analyst gets an error naming the tag, which tells them what to
    request (governance.md, section 2).
- **Harder:**
  - Every rebuild must re-apply tags. dbt does it through `persist_docs`;
    `warehouse.py` does it explicitly, with a test.
  - Anyone with `categoryAdmin` can unprotect everything in one call without
    the schema changing. That role must be treated as privileged, and checked
    by a refusal test, not by reading schemas.
- **Not solved:**
  - Bronze, where the phone numbers are. The fix is upstream: stop extracting
    `street_address` and `phone`, which no model uses.
  - Silver views carrying `buyer_id` are protected only if they become tables.
- **Revisit when:**
  - the admin removes the project-wide fine-grained read: then rerun the
    refusal test and record it
  - or a consumer outside the group needs a *shape*, not a permission: then a
    view for that consumer, over the tagged table, is the right tool, and
    the two options combine rather than compete.
