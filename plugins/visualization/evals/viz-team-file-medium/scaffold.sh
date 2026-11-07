#!/usr/bin/env bash
# A git repository with a tracked docs/conventions/rendered-views.yaml setting file.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/rendered-views-repo.sh" team-file
