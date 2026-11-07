#!/usr/bin/env bash
# A git repository with an untracked, gitignored docs/conventions/rendered-views.local.yaml setting
# file, and no team file.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/rendered-views-repo.sh" personal-file
