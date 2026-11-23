#!/usr/bin/env bash
set -euo pipefail

seed="$(dirname "${BASH_SOURCE[0]}")/../fixtures/td-seed.sh"
bash "$seed" td-build-report.sh=scripts/build-report.sh td-build-report.test.sh=tests/build-report.test.sh td-CLAUDE.md=CLAUDE.md
