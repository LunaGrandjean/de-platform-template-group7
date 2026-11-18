# Reproducing the ingestion image from nothing

> **Status:** steps 0 to 6 were run on 2026-11-12 and the output below is the real
> output. **Step 7 (retention) was completed on 2026-11-16: the probe tag was deleted in the Docker Hub web UI, and the listings before and after are below.**
>
> How it was captured: each command was run in PowerShell, and the script that ran it
> echoed the command with a `PS>` prefix just before its output. Nothing was retyped
> from memory. Three places are shortened and each one says so where it happens.

The claim under test: a machine that has never built this image can pull it by its tag
and produce the same output as the machine that built it. The image under test is
`group7-ingestion` (the Step 3 orders extractor). The dbt image was pushed the same way
but is not the one reproduced here.

| | |
|---|---|
| Commit the image was built from | `90355ad` |
| Tag | `2026-11-12-90355ad` |
| Reference | `omara11/group7-ingestion:2026-11-12-90355ad` |
| Digest from `docker push` | `sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a` |
| Digest from `docker pull` | `sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a` |
| Digests match | yes |
| Output of run 1 and run 2 | identical |

`<ref>` below is `omara11/group7-ingestion:2026-11-12-90355ad`.

## 0. Pin the input

The count must not move between the two runs. The live traffic generator keeps adding
orders to the source database, so it was stopped first and the source state recorded.

```text
PS> docker compose stop load-generator
 Container albert-marketplace-load-generator-1  Stopping
 Container albert-marketplace-load-generator-1  Stopped
PS> docker compose up -d db
 Container albert-marketplace-db-1  Running
PS> docker compose exec -T db psql -U postgres -d marketplace -At -c "select count(*), max(order_id) from public.orders"
224856|224901
```

## 1. Build from a committed tree, push, and record the push digest

The tree was committed first (`90355ad`), and the build inputs were checked to be
identical to that commit, so the SHA in the tag is the SHA of the code. The image carries
the same SHA in its `org.opencontainers.image.revision` label. The `PS>` prompt is not in
this part of the output because the build and push ran inside a script; the commands were
exactly these:

```text
PS> docker build -q -f ingestion/Dockerfile --build-arg GIT_SHA=90355ad -t omara11/group7-ingestion:2026-11-12-90355ad .
sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a
ingestion build exit: 0
PS> docker push omara11/group7-ingestion:2026-11-12-90355ad
The push refers to repository [docker.io/omara11/group7-ingestion]
[142 repeated "<layer id>: Waiting" progress lines omitted here]
dbeb2af0e7bd: Pushed
b0113780077d: Pushed
86dbfd7c8139: Pushed
a843489e8dfc: Pushed
b490dc5245cf: Pushed
2e8ff2a71e95: Pushed
f9f25941dc13: Pushed
f1d95a98e4ee: Pushed
84a2afebaf4d: Pushed
6efb069f76ed: Pushed
2026-11-12-90355ad: digest: sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a size: 856
push exit code: 0   elapsed: 83 s
```

Push digest: `sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a`

The dbt image, pushed the same way (last line of its push, which took 172 s):

```text
2026-11-12-90355ad: digest: sha256:002f3c71cd6aa001ff3a67d639ffe2a5d11f4439ee7524ef85bdd2092e940d29 size: 856
```

Docker Hub's own view of both repositories, read afterwards with an anonymous request
(no credentials sent), which also shows they are public and carry no `latest` tag:

```text
=== omara11/group7-ingestion  (anonymous request, no credentials sent)
is_private      : False
repository      : omara11/group7-ingestion
tag             : 2026-11-12-90355ad
compressed size : 140.5 MiB (147371411 bytes)
hub digest      : sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a
matches my push : True
last_updated    : 2026-11-12T18:01:02.09307Z
tags named latest: 0
=== omara11/group7-transform  (anonymous request, no credentials sent)
is_private      : False
repository      : omara11/group7-transform
tag             : 2026-11-12-90355ad
compressed size : 297.3 MiB (311776308 bytes)
hub digest      : sha256:002f3c71cd6aa001ff3a67d639ffe2a5d11f4439ee7524ef85bdd2092e940d29
matches my push : True
last_updated    : 2026-11-12T18:03:55.946263Z
tags named latest: 0
```

## 2. First run: what the job produced

Local output only: nothing is written to the Bronze bucket, and the cursor lives in a
fresh volume.

```text
PS> docker volume rm g07_repro 2>$null
PS> docker run --rm --network albert-marketplace_default -e PGHOST=db -e PGDATABASE=marketplace -e PGUSER=postgres -e PGPASSWORD=postgres -e SOURCE_ID=g07-repro -v g07_repro:/state omara11/group7-ingestion:2026-11-12-90355ad python ingestion/extract_orders.py --once --local-output /state/bronze --state-file /state/orders-repro.json
{"rows": 224856, "batches": 45, "last_order_id": 224901}
exit: 0
```

## 3. Delete the image from this machine

Deleting is the whole test. Running again without it proves nothing.

```text
PS> docker rmi omara11/group7-ingestion:2026-11-12-90355ad
Untagged: omara11/group7-ingestion:2026-11-12-90355ad
Deleted: sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a
PS> docker images omara11/group7-ingestion
WARNING: This output is designed for human readability. For machine-readable output, please use --format.
IMAGE   ID             DISK USAGE   CONTENT SIZE   EXTRA
```

The listing is empty: no `group7-ingestion` image is left. (The unfiltered `docker images`
was run first and showed the same, but it also lists images from other projects on this
machine, so those lines are not reproduced here. This is the first shortened place.)

## 4. Pull it back by tag, with no stored credentials

The repository is public, so no login is needed. To prove it, this pull ran with an empty
Docker configuration folder and an explicit daemon address, so the client had no
credentials to send.

```text
PS> $env:DOCKER_CONFIG = "<an empty folder with config.json = {}>"
PS> $env:DOCKER_HOST = "npipe:////./pipe/dockerDesktopLinuxEngine"
PS> docker pull omara11/group7-ingestion:2026-11-12-90355ad
2026-11-12-90355ad: Pulling from omara11/group7-ingestion
a843489e8dfc: Download complete
Digest: sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a
Status: Downloaded newer image for omara11/group7-ingestion:2026-11-12-90355ad
docker.io/omara11/group7-ingestion:2026-11-12-90355ad
pull exit: 0
```

(The real folder path is a temporary directory and is shortened to a description. This is
the second shortened place.) Only one layer was downloaded: the others are shared with
other images already on this machine, such as the dbt image, and Docker reuses them. The
image itself, its manifest and configuration, was deleted in step 3 and came back by tag.

Pull digest: `sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a`

## 5. Second run: the same output

A fresh volume again, so the cursor starts from zero as it did the first time.

```text
PS> docker volume rm g07_repro
g07_repro
PS> docker run --rm --network albert-marketplace_default -e PGHOST=db -e PGDATABASE=marketplace -e PGUSER=postgres -e PGPASSWORD=postgres -e SOURCE_ID=g07-repro -v g07_repro:/state omara11/group7-ingestion:2026-11-12-90355ad python ingestion/extract_orders.py --once --local-output /state/bronze --state-file /state/orders-repro.json
{"rows": 224856, "batches": 45, "last_order_id": 224901}
exit: 0
```

## 6. The two digests, side by side

| | Digest |
|---|---|
| From `docker push` (step 1) | `sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a` |
| From `docker pull` (step 4) | `sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a` |

Match: yes. The script that compared them printed:

```text
digests equal      : True
run 1 output       : {"rows": 224856, "batches": 45, "last_order_id": 224901}
run 2 output       : {"rows": 224856, "batches": 45, "last_order_id": 224901}
outputs identical  : True
```

## 7. Retention: the deletion that was actually run

**Done on 2026-11-16.** The probe tag was pushed on 2026-11-12 and deleted on 2026-11-16
by the account owner, in the Docker Hub web UI. The policy is in
[ADR 0006](adr/0006-image-tags.md). This section records the deletion that enforces it. Only one build per image exists, and the policy
keeps the tag in use, so the deletion is exercised on a probe tag: a second name
(`2026-11-12-probe`) for the same image, pushed once and then deleted. The
evidence is the public tag listing before and after, with the deletion done in the
Docker Hub web UI in between.

The probe tag was created and pushed first. Every layer already existed on Docker Hub, so
no new content was published, and the digest equals the build's digest. (The repeated
`<layer id>: Waiting` progress lines are omitted here; this is the third shortened place.)

```text
PS> docker tag omara11/group7-ingestion:2026-11-12-90355ad omara11/group7-ingestion:2026-11-12-probe
tag exit: 0
PS> docker push omara11/group7-ingestion:2026-11-12-probe
The push refers to repository [docker.io/omara11/group7-ingestion]
[repeated "<layer id>: Waiting" progress lines omitted]
84a2afebaf4d: Layer already exists
dbeb2af0e7bd: Layer already exists
86dbfd7c8139: Layer already exists
2e8ff2a71e95: Layer already exists
b490dc5245cf: Layer already exists
a843489e8dfc: Already exists
f9f25941dc13: Layer already exists
f1d95a98e4ee: Layer already exists
b0113780077d: Layer already exists
6efb069f76ed: Layer already exists
2026-11-12-probe: digest: sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a size: 856
push exit: 0
```

Before the deletion, read with an anonymous request:

```text
PS> (Invoke-RestMethod "https://hub.docker.com/v2/repositories/omara11/group7-ingestion/tags?page_size=100").results | Select-Object name, digest, last_updated

name         : 2026-11-12-probe
digest       : sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a
last_updated : 2026-11-12T18:09:46.736126Z

name         : 2026-11-12-90355ad
digest       : sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a
last_updated : 2026-11-12T18:01:02.09307Z

tags listed: 2   probe present: True
probe digest equals build digest: True
```

The probe tag was then deleted in the Docker Hub web UI (repository, **Tags**,
`2026-11-12-probe`, **Delete**) by the account owner. After the deletion, read with an
anonymous request on 2026-11-16:

```text
PS> (Invoke-RestMethod "https://hub.docker.com/v2/repositories/omara11/group7-ingestion/tags?page_size=100").results | Select-Object name, digest, last_updated

name         : 2026-11-12-90355ad
digest       : sha256:1ac3386beb286b286e593563e12007e1aa7c194ef6b7812d6e6ccd5e0e586f1a
last_updated : 2026-11-12T18:01:02.09307Z

tags listed: 1   probe present: False
build tag present: True
build digest unchanged: True
```

The dbt repository was not touched. Its only tag is still `2026-11-12-90355ad`, digest
`sha256:002f3c71cd6aa001ff3a67d639ffe2a5d11f4439ee7524ef85bdd2092e940d29`.

The leftover local name for the probe was removed as well; the image stays on the machine
under its build tag:

```text
PS> docker rmi omara11/group7-ingestion:2026-11-12-probe
Untagged: omara11/group7-ingestion:2026-11-12-probe
exit: 0
```

The listing command is:

```
(Invoke-RestMethod "https://hub.docker.com/v2/repositories/omara11/group7-ingestion/tags?page_size=100").results | Select-Object name, digest, last_updated
```

## What this does and does not prove

- It proves the image can be deleted from the machine that built it and come back, by
  tag, byte for byte: the push and pull digests are equal, and so is the job's output.
- The input was pinned (the generator was stopped, and the count was recorded before and
  after), so the equal output is not luck. A different machine would have a different
  database, so its row count would differ; there the digest is the evidence.
- This ran on the same machine that built the image, with its other images present. The
  stronger test is for a teammate who has never built it to run step 4 on their machine
  and compare the digest with the one above.
