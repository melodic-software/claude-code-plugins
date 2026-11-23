#!/usr/bin/env bash
set -euo pipefail

seed="$(dirname "${BASH_SOURCE[0]}")/../fixtures/td-seed.sh"
bash "$seed" td-release.sh=scripts/release.sh td-VERSION=VERSION td-release-CLAUDE.md=CLAUDE.md
