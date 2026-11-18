# Ingestion job: the Step 3 Python extractors, packaged (Step 6).
#
# Build from the REPOSITORY ROOT, so the root .dockerignore applies:
#   docker build -f ingestion/Dockerfile --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t <image>:<tag> .
#
# Pinned at both ends:
#   - the base image to a patch version (python:3.12.12-slim-bookworm), and
#   - every Python dependency by uv.lock (exact versions plus hashes), installed
#     with --locked, which fails the build if uv.lock no longer matches pyproject.toml
#     (--frozen would skip that check and install a stale lock without a word).
FROM python:3.12.12-slim-bookworm

# uv, pinned, copied from its official image: nothing else from that image comes along.
COPY --from=ghcr.io/astral-sh/uv:0.9.30 /uv /usr/local/bin/uv

ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_COMPILE_BYTECODE=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /app

# 1. The manifest goes in before the code: a code change rebuilds only the layers
#    below, and the slow dependency install is reused from the cache.
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-cache --no-dev --no-install-project \
    && useradd --create-home --uid 10001 --shell /usr/sbin/nologin ingest \
    && mkdir /state \
    && chown ingest /state

# 2. The code. ingestion/ only; .dockerignore keeps .env, data/ and .git out.
COPY ingestion/ ./ingestion/

ARG GIT_SHA=unknown
LABEL org.opencontainers.image.title="group7-ingestion" \
      org.opencontainers.image.description="Albert's Marketplace Step 3 ingestion jobs" \
      org.opencontainers.image.revision="${GIT_SHA}"

# Nothing runs as root, and nothing secret lives in the image. Everything the job
# needs arrives at run time: PGHOST, PGDATABASE, PGUSER, PGPASSWORD, SOURCE_ID,
# GCP_PROJECT_ID and BRONZE_BUCKET as -e values, and the Google credentials as a
# read-only mount referenced by GOOGLE_APPLICATION_CREDENTIALS.
#
# The extractor's cursor is a file, and a container keeps nothing. Mount a named
# volume at /state and pass --state-file /state/orders.json, or every run starts
# again from order 0.
USER ingest

# No default that writes to production: a bare `docker run` prints the options.
# The job to run is always chosen explicitly, for example
#   python ingestion/extract_orders.py --once --state-file /state/orders.json
#   python ingestion/consume_clickstream.py
CMD ["python", "ingestion/extract_orders.py", "--help"]
