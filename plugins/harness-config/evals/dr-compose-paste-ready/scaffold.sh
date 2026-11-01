#!/usr/bin/env bash
# The quay repo with one narrow allow rule, committed on main.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" plain
