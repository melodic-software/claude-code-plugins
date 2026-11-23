#!/usr/bin/env bash
set -euo pipefail

seed="$(dirname "${BASH_SOURCE[0]}")/../fixtures/td-seed.sh"
bash "$seed" td-project-lane.md=.claude/tidy-lanes/shell-tooling.md td-rotate-logs.sh=ops/rotate-logs.sh td-build-report.sh=scripts/build-report.sh
git checkout -q -b feature/ops-logs
