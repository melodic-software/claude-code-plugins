#!/usr/bin/env bash
# The quay repo with allow rules of several shapes, committed on main.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" state-entry
