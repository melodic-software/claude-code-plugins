#!/usr/bin/env bash
# Seeds a worker note with four plain idioms or field terms and one real figure, each on its own line.
set -euo pipefail

mkdir -p docs
cat > docs/worker-notes.md <<'MD'
# Ingest worker notes

The retry limit lives in `config/ingest.toml`, under the `[worker]` table.

After a deploy, the upload queue drains in about four minutes.

The export thread starves when the nightly batch job holds every database connection.

The thumbnail cache is warm once the first hundred requests have been served.

Stale lockfiles murder the `02:00` nightly build.
MD
