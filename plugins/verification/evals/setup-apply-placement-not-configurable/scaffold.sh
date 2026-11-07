#!/usr/bin/env bash
# A committed repository with no docs/conventions/verification.yaml and no .gitignore.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/settings-repo.sh" none
