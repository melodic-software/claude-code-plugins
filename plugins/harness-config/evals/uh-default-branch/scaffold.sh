#!/usr/bin/env bash
# The quay repo with instruction surfaces and two hooks, committed on main.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" unhobble
