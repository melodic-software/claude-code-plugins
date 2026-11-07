#!/usr/bin/env bash
# The audit tree plus docs/BETA.md beside docs/beta.md.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fn-repo.sh" collision
