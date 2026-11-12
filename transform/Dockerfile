# dbt runner: the Step 5 project (silver and gold on BigQuery), packaged (Step 6).
#
# Build from the REPOSITORY ROOT, so the root .dockerignore applies:
#   docker build -f transform/Dockerfile --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t <image>:<tag> .
#
# Pinned at both ends:
#   - the base image to a patch version (python:3.12.12-slim-bookworm),
#   - dbt-core and dbt-bigquery by transform/uv.lock (--frozen), and
#   - dbt_utils by transform/package-lock.yml (dbt deps installs exactly that).
FROM python:3.12.12-slim-bookworm

# uv, pinned, copied from its official image: nothing else from that image comes along.
COPY --from=ghcr.io/astral-sh/uv:0.9.30 /uv /usr/local/bin/uv

# dbt writes target/ and logs/ at run time. They go to /tmp so the non-root user can
# write them; mount a volume there to keep them (dbt docs generate needs target/).
ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_COMPILE_BYTECODE=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    DBT_PROFILES_DIR=/transform \
    DBT_TARGET_PATH=/tmp/dbt/target \
    DBT_LOG_PATH=/tmp/dbt/logs \
    DBT_SEND_ANONYMOUS_USAGE_STATS=false

WORKDIR /transform

# 1. The manifest goes in before the project: model changes rebuild only the layers
#    below, and the slow dependency install is reused from the cache.
COPY transform/pyproject.toml transform/uv.lock ./
RUN uv sync --frozen --no-cache --no-dev --no-install-project \
    && useradd --create-home --uid 10001 --shell /usr/sbin/nologin dbt

# 2. The dbt packages, installed at build time from package-lock.yml, so a run needs
#    no download. dbt deps logs to /tmp/dbt, which is removed so the runtime user
#    creates its own. dbt_utils also ships its own integration tests, including a
#    folder named .env of empty CI templates; dbt never uses them, and removing them
#    leaves the image with no .env-named path at all (secret scanners flag the name).
COPY transform/dbt_project.yml transform/packages.yml transform/package-lock.yml transform/profiles.yml ./
RUN dbt deps && rm -rf /tmp/dbt /transform/dbt_packages/*/integration_tests

# 3. The project. .dockerignore keeps target/, dbt_packages/, logs/ and any .env out.
COPY transform/ ./

ARG GIT_SHA=unknown
LABEL org.opencontainers.image.title="group7-transform" \
      org.opencontainers.image.description="Albert's Marketplace Step 5 dbt project (BigQuery)" \
      org.opencontainers.image.revision="${GIT_SHA}"

# Nothing runs as root, and nothing secret lives in the image: profiles.yml uses
# Application Default Credentials. At run time mount the credentials file read-only
# and point GOOGLE_APPLICATION_CREDENTIALS at it; GCP_PROJECT_ID defaults to
# data-engineering-i1 in profiles.yml.
USER dbt

# No default that builds anything: a bare `docker run` prints dbt's help. The command
# is always chosen explicitly, for example
#   docker run ... <image> build
#   docker run ... <image> source freshness
ENTRYPOINT ["dbt"]
CMD ["--help"]
