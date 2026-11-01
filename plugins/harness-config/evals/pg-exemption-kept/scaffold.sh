#!/usr/bin/env bash
# The quay repo with one broad grant that CLAUDE.md declares deliberate, committed on main.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" exempt
