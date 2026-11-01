#!/usr/bin/env bash
# The quay repo with fragile allow grants and a bundled plugin, committed on main.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" grants
