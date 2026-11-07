#!/usr/bin/env bash
# A committed repository with no .gitignore, no .work/ and no docs/conventions/verification.yaml.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/settings-repo.sh" none
