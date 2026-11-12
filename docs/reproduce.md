# Reproducing the ingestion image from nothing

> **Status: NOT YET RUN.** This file holds the commands and the empty slots for the
> transcript. It is **not evidence** until every slot below is replaced by real terminal
> output, with the prompts and any error messages left in. A description of what
> happened proves nothing; two matching `sha256:` values do.

The claim under test: a machine that has never built this image can pull it by its tag
and produce the same output as the machine that built it. The image under test is
`group7-ingestion` (the Step 3 orders extractor). The dbt image is built and tested the
same way but is not the one reproduced here.

`<tag>` is `YYYY-MM-DD-<short sha>` (see [ADR 0006](adr/0006-image-tags.md)).
`<ref>` is `<dockerhub-user>/group7-ingestion:<tag>`, a public Docker Hub repository.

## 0. Pin the input

The count must not move between the two runs. The live traffic generator keeps adding
orders to the source database, so stop it first and record the source state. If a count
moves anyway, say so here and re-pin; do not call a different number "close enough".

```
docker compose stop load-generator
docker compose up -d db
docker compose exec -T db psql -U postgres -d marketplace -At -c "select count(*), max(order_id) from public.orders"
```

```text
<paste the real terminal output here>
```

## 1. Build from a committed tree, push, and record the push digest

Build from the repository root, tagged only with the registry reference so there is a
single tag to delete in step 3. The commit must exist first: the SHA in the tag has to
be the SHA of the code. `docker login` is interactive and is done by the account owner;
it is not part of the transcript.

```
docker build -f ingestion/Dockerfile --build-arg GIT_SHA=<short sha> -t <ref> .
docker push <ref>
```

```text
<paste the real terminal output here, including the line "<tag>: digest: sha256:... size: ...">
```

Push digest: `sha256:<fill in from the transcript above>`

## 2. First run: what the job produced

Local output only: nothing is written to the Bronze bucket, and the cursor lives in a
fresh volume.

```
docker volume rm g07_repro 2>$null
docker run --rm --network albert-marketplace_default -e PGHOST=db -e PGDATABASE=marketplace -e PGUSER=postgres -e PGPASSWORD=postgres -e SOURCE_ID=g07-repro -v g07_repro:/state <ref> python ingestion/extract_orders.py --once --local-output /state/bronze --state-file /state/orders-repro.json
```

```text
<paste the real terminal output here: the JSON line with rows, batches and last_order_id>
```

## 3. Delete the image from this machine

Deleting is the whole test. Running again without it proves nothing.

```
docker rmi <ref>
docker images
```

```text
<paste the real terminal output here: docker images must no longer list group7-ingestion>
```

## 4. Pull it back by tag

No login is needed: the repository is public. If this step asks for credentials, the
repository is not public and the reproduction is not valid.

```
docker pull <ref>
```

```text
<paste the real terminal output here, including the line "Digest: sha256:...">
```

Pull digest: `sha256:<fill in from the transcript above>`

## 5. Second run: the same output

A fresh volume again, so the cursor starts from zero as it did the first time.

```
docker volume rm g07_repro
docker run --rm --network albert-marketplace_default -e PGHOST=db -e PGDATABASE=marketplace -e PGUSER=postgres -e PGPASSWORD=postgres -e SOURCE_ID=g07-repro -v g07_repro:/state <ref> python ingestion/extract_orders.py --once --local-output /state/bronze --state-file /state/orders-repro.json
```

```text
<paste the real terminal output here: it must match step 2 exactly>
```

## 6. The two digests, side by side

| | Digest |
|---|---|
| From `docker push` (step 1) | `sha256:<fill in>` |
| From `docker pull` (step 4) | `sha256:<fill in>` |

Match: <yes / no, and if no, why>

## 7. Retention: the deletion that was actually run

The policy is in [ADR 0006](adr/0006-image-tags.md). This section records the deletion
that enforced it. Docker Hub tags are deleted in the web UI, so the evidence is the
public tag listing before and after.

```
(Invoke-RestMethod "https://hub.docker.com/v2/repositories/<dockerhub-user>/group7-ingestion/tags?page_size=100").results | Select-Object name, last_updated
```

```text
<before the deletion: paste the real terminal output here>
```

Then delete the tag in the Docker Hub UI (repository, **Tags**, select, **Delete**), and
run the same listing again.

```text
<after the deletion: paste the real terminal output here; the deleted tag must be gone>
```

## What a fresh clone will not reproduce

The row count and `last_order_id` depend on the orders in the source database at the
moment of the run, so a teammate's numbers will differ from ours. What must hold, on any
machine, is that the two runs on the same input agree with each other, and that the pull
digest equals the push digest.
