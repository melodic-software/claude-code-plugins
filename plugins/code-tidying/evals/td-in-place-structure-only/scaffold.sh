#!/usr/bin/env bash
# Seeds the report script, its behavior-pin test and CLAUDE.md on main, switches to a feature branch, and leaves an untracked WIP note.
set -euo pipefail

seed="$(dirname "${BASH_SOURCE[0]}")/../fixtures/td-seed.sh"
bash "$seed" td-build-report.sh=scripts/build-report.sh td-build-report.test.sh=tests/build-report.test.sh td-CLAUDE.md=CLAUDE.md
git checkout -q -b feature/report-tooling
mkdir -p notes
printf '%s\n' "parallel-session draft, not part of any tidy" >notes/wip-draft.md
