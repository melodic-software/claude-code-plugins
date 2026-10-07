#!/usr/bin/env bash
# Seeds scripts/release.sh (tidyable but declared protected in CLAUDE.md) and VERSION on main, with no remote.
set -euo pipefail

seed="$(dirname "${BASH_SOURCE[0]}")/../fixtures/td-seed.sh"
bash "$seed" td-release.sh=scripts/release.sh td-VERSION=VERSION td-release-CLAUDE.md=CLAUDE.md
