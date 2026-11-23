# Project status

Updated 2026-11-23. Steps 1 to 10 are integrated into `main`; the remaining
items below concern cloud permissions, evidence and final submission.

## Integration and recorded runs

- PR #10 (governance) was merged into the Step 9 branch, then PR #9 was merged
  into `main`, both with merge commits on 2026-11-22. The resulting main commit
  is [`3f2b968`](https://github.com/LunaGrandjean/de-platform-template-group7/commit/3f2b9683a32c99601f48d38f4fa710e3bdb4fb74).
- [Terraform CI after the merge](https://github.com/LunaGrandjean/de-platform-template-group7/actions/runs/45054017414)
  passed formatting, backend-free initialisation and validation. These checks
  do not contact GCP or prove that a live plan has no changes.
- The DAG defaults to ingestion `2026-11-17-e8df6e5` and transform
  `2026-11-22-c565e73`. The transform image includes the daily/full selectors
  and preserves the Gold `buyer_id` policy tag.
- [Two recorded DAG runs](evidence/step10/dag-run-new-image.txt) on 2026-11-22
  passed all three tasks: dbt `PASS=56 WARN=1 ERROR=0 SKIP=0`. Both extracted
  zero orders because their intervals were beyond the restored source's last
  order date. They verify the image, selector and tag preservation; they do
  not demonstrate new orders reaching Gold. Earlier scheduled-data and
  back-fill checks are recorded in [orchestration.md](orchestration.md).

## Terraform apply

On 2026-11-22, Émile reported applying Steps 9 and 10 together from Anas's
branch and checking the result in GCP:

- Four convention labels applied to the Bronze bucket and all four datasets.
- On `g07_warehouse`, the four non-owner members changed from `dataEditor`
  to `dataViewer`.
- The existing taxonomy and policy tags were imported into Terraform, with
  fine-grained tag-reader grants for the five members.
- A follow-up plan reported no remaining changes.

This is the operator's confirmation shared with the group. Its apply output
and final plan transcript have not been committed. The older
[Step 9 plan](evidence/step9/terraform-plan-labels.txt) and
[Step 10 plan](evidence/step10/terraform-plan.txt) remain dated pre-apply
evidence; they are not proof of this later apply. Attach the actual apply and
post-apply plan output when available, with credentials and identifiers
reviewed before publication. This documentation update did not rerun GCP checks.

## Remaining cloud work

| Item | Current state | Owner / next action |
|---|---|---|
| Budget | Declared but disabled; no group budget notification has been demonstrated | Course admin: provide billing account access or create the configured budget, then verify its recipient. See [costs.md](costs.md#2-budget-alert). |
| Denied read of `buyer_id` | Not demonstrated: student accounts inherit fine-grained access from the shared project | Course admin: provide an identity with table access but no tag-reader or inherited fine-grained grant, and capture a denied query. See [governance gaps](governance.md#5-where-the-matrix-and-reality-differ). |
| Pipeline service account | Declared, not created; Airflow still uses an operator's ADC | Course admin and operator: create/adopt `g07-pipeline`, grant job execution and impersonation access, apply its scoped grants and verify a DAG run before removing inherited write access. See [infra.md](infra.md#the-pipelines-identity-steps-7-and-8). |
| Broad inherited access and untagged personal data | Dataset role reduction does not remove project defaults; Bronze contact data and Silver views retain the documented exposure | Course admin and dataset owners: address the [seven governance gaps](governance.md#5-where-the-matrix-and-reality-differ). |

## Submission and defence

- [x] Integrate Steps 1 to 10 through reviewed PRs while preserving commits.
- [ ] Attach Émile's combined apply and final plan transcripts.
- [ ] Confirm the cohort identifier, required repository name and private visibility. At this update the repository is public and remains a fork.
- [ ] Verify every member and `Charlestng` have accepted collaborator access, and confirm that the repository URL and team were submitted as requested.
- [ ] Verify each member's contribution history before marking the README checklist complete.
- [ ] Record a 5–8 minute demonstration of the running pipeline, with every member speaking; add an accessible video link to the README.
- [ ] Record who will defend each ADR: at least two per member, none written alone by that member. No allocation has been supplied yet.
- [ ] Rehearse the ten-minute group pitch, including an actual failure and its diagnosis.

The cloud limitations stay explicit in the submission until the corresponding
checks have been completed. Merged code and a passing CI check do not replace
live enforcement evidence.
