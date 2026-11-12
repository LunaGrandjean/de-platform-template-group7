# ADR 0006: Image tags, registry and retention

- **Status:** proposed. It becomes accepted when the retention policy has been executed and its output is pasted below.
- **Date:** 2026-11-12
- **Author:** group 7, Step 6 (container images)
- **Lesson:** L06

## Context

Both jobs are now images: `group7-ingestion` (the Step 3 extractors, built from
`ingestion/`) and `group7-transform` (the Step 5 dbt project, built from
`transform/`). Facts that decide the tagging and the registry, with where each comes
from:

- **A tag is a name, not a version.** It can be moved to a different build, and
  `latest` moves on every push. A scheduler that pulls `latest` after a back-fill runs
  last Monday's data through this Wednesday's code, and nothing reports an error
  (lesson 6). The step forbids `latest` outright.
- **Size, measured locally on 2026-11-12** (uncompressed, `docker images`):
  `group7-ingestion` 605 MB; `group7-transform` 1.44 GB, of which 892 MB is the Python
  environment (the Google client libraries, pyarrow and pandas that `dbt-bigquery`
  needs) and 200 MiB is compiled bytecode. The compressed size in the registry will be
  recorded here after the first push.
- **What is in the images.** Our ingestion code and dbt models, and nothing else of
  ours. No secrets and no data: the `.dockerignore` is an allow-list, a build with nine
  planted decoy secret files let none of them in, and `transform/profiles.yml` holds no
  credentials (it uses Application Default Credentials mounted at run time).
- **A shared Artifact Registry repository exists.** `dataeng` in project
  `data-engineering-i1`, region `europe-west1`, described as the students' images. Read
  through the API on 2026-11-12: 33 image versions, 1.72 GB, no cleanup policy shown.
  Other groups name images `groupN-<job>` and tag them with a date and a commit.
- **Our rights on that repository**, checked with `testIamPermissions` on 2026-11-12
  (a read-only call): we can download, upload and create or update tags; we **cannot**
  delete artifacts or tags, update the repository or change its IAM policy.
- **Prices.** Artifact Registry: $0.100 per GiB-month above a free 0.5 GiB (lesson 6).
  Docker Hub: free for public repositories. The step requires a retention policy that
  was actually executed.

## Options considered

What goes in a tag:

| Option | For | Against |
|---|---|---|
| Date only (`2026-11-12`) | Readable and sortable | Two pushes in a day collide, and it does not say which commit |
| Git short SHA only | Names the exact code | Not sortable, and carries no date for a retention rule |
| Semantic version | Meaningful to people | Needs release discipline and a manual bump nobody will keep up in a ten-week project |
| **Date + git short SHA** (`2026-11-12-629013c`) | Sortable, unambiguous, ties the image to a commit | Longer, and the SHA is only true if the image is built from a committed tree |
| `latest` | Convenient | Moves, cannot be rolled back to, forbidden by the step |

Where the images live:

| Option | For | Against |
|---|---|---|
| Artifact Registry `dataeng` (shared) | Private; same project, region and IAM as the data; the class convention | **We cannot delete from it**, so the retention policy could not be executed; costs per GiB above the free 0.5 GiB; shared with other groups |
| **Docker Hub, public repositories** | Free; we control deletion, so the policy can be executed; anyone can pull with no login and no `gcloud`, so the reproduction really can run on a machine that was never set up | Anyone can read our code and models; anonymous pulls are rate-limited; needs a personal account; leaves the project's IAM |
| Our own Artifact Registry repository | Could give us delete rights | Whether we may create one is untested; extra cost and set-up |

## Decision

- **Tag:** `YYYY-MM-DD-<7-character commit SHA>`, with the UTC date of the build, for
  example `2026-11-12-629013c`. An image is built only from a committed tree, so the SHA
  in the tag is the SHA of the code in the image. Nothing is ever tagged `latest`, and
  an existing tag is never pushed again with different content.
- **Registry:** Docker Hub, in two public repositories,
  `<dockerhub-user>/group7-ingestion` and `<dockerhub-user>/group7-transform`. It was
  chosen because it is the option where we can both publish and delete, which the
  retention policy needs, and because a public pull needs no credentials.
- **Provenance in the image:** the build argument `GIT_SHA` is stored in the label
  `org.opencontainers.image.revision`, so an image says which commit built it even if
  its tag is lost.
- **Digest on record:** after each push the digest is written next to the tag in
  `docs/reproduce.md`. The tag is the name; the digest is the evidence.

## Rolling back

Replace `<image>` with `group7-ingestion` or `group7-transform`, and `<previous-tag>`
with the tag you want back.

1. List the tags that exist (the endpoint is public, so no login is needed). In
   PowerShell:
   `(Invoke-RestMethod "https://hub.docker.com/v2/repositories/<dockerhub-user>/<image>/tags?page_size=100").results | Select-Object name, last_updated`
   or, in a POSIX shell:
   `curl -s "https://hub.docker.com/v2/repositories/<dockerhub-user>/<image>/tags?page_size=100"`
2. Pull the previous build:
   `docker pull <dockerhub-user>/<image>:<previous-tag>`
3. Check it is the build you recorded:
   `docker inspect --format "{{index .RepoDigests 0}}" <dockerhub-user>/<image>:<previous-tag>`,
   then compare with the digest in `docs/reproduce.md`.
4. Point the job at it by changing the tag wherever the job names the image. That is a
   single place per job; it must stay a single place.
5. Do not rebuild and push a "fixed" image under the old tag. A rollback moves a
   reference to an older tag; it never rewrites one.

## Retention policy (proposed)

Per image, three tags survive: the one in use, the one before it (the rollback target),
and any tag cited as evidence in `docs/reproduce.md`. Every other tag is deleted at the
next promotion of a new tag, and no uncited tag outlives 30 days.

Enforcement is a deletion in the Docker Hub web UI (repository, **Tags**, select the
tags, **Delete**). The evidence is the public tag listing from step 1 of the rollback,
captured before and after the deletion, so the output shows the tag disappear.

**Evidence of enforcement: none yet.** The policy has not been executed. Until a
deletion has been run and the before-and-after listings are pasted below, this ADR stays
proposed.

```text
<before: paste the tag listing here>
<after the deletion: paste the tag listing here>
```

## Consequences

- **Easier:** a specific build can be named, pulled and checked by digest, by anyone,
  with only Docker. The rollback is five commands and rewrites nothing, and the
  retention policy can actually be executed.
- **Harder:** an image can only be built after its commit exists, so the commit comes
  before the push. The images are public: anyone can read our ingestion code and dbt
  models. That is acceptable only because the images hold no secret and no data, so the
  `.dockerignore` allow-list and the no-`.env` check must stay in place.
- **Watch:** Docker Hub rate-limits anonymous pulls. A scheduler should pull only when
  the tag it names changes, not on every run. The free plan also limits private
  repositories, so going private later is a decision to check against the account page.
- **Cost:** none for the registry. Record the compressed size of each push here.
- **Not chosen, but still there:** the shared Artifact Registry. It holds the other
  groups' images, and we can push to it, so it remains a fallback for pulling from
  inside the project if delete rights are ever granted.

## What would change our mind

- **Delete rights granted on the shared Artifact Registry:** its privacy and IAM would
  then outweigh Docker Hub's convenience. The registry host, the rollback commands and
  the retention command would change, and this ADR would be rewritten.
- **The images must stay private:** a private repository (the free plan allows few), or
  Artifact Registry with delete rights.
- **Anonymous pull limits start to bite** (for example when the scheduler pulls often):
  authenticate the pull, or mirror the images inside the project.
- **The compressed images grow large:** slim the transform image first (dropping the
  200 MiB of bytecode is the first lever).
- **Several releases a day, or a consumer that needs compatibility guarantees:** the
  date-and-commit tag still names a build, but a semantic version would then say
  something a date cannot.
