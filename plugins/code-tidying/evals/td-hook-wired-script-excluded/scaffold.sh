#!/usr/bin/env bash
# Seeds a lane script, a tidyable hook script under scripts/hooks/ wired in .claude/settings.json, and the test, then switches to a feature branch.
set -euo pipefail

seed="$(dirname "${BASH_SOURCE[0]}")/../fixtures/td-seed.sh"
bash "$seed" td-build-report.sh=scripts/build-report.sh td-build-report.test.sh=tests/build-report.test.sh td-CLAUDE.md=CLAUDE.md td-check-bash.sh=scripts/hooks/check-bash.sh td-settings.json=.claude/settings.json
git checkout -q -b feature/report-tooling
