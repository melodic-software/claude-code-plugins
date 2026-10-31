#!/usr/bin/env bash
# Seeds a doc with a colon crutch and a colon that introduces a list.
set -euo pipefail

mkdir -p docs
cat > docs/paging.md <<'MD'
# Paging policy

The short version: the job retries three times before it pages anyone.

The job reads three settings:

- `RETRY_LIMIT`, the number of retries before a page
- `RETRY_DELAY`, the seconds between retries
- `PAGE_TARGET`, the rotation that receives the page
MD
