#!/usr/bin/env bash
# The quay repo with ruff in pre-commit and CI, no database, and dependency-bump history.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" automation
