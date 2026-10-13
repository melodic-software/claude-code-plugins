#!/usr/bin/env bash
# Seeds the workspace as the target checkout: one commit on main whose tracked
# .claude/source-control.md adopts the loop lane at c3-autonomous, so the resolved rung is
# merge-capable and the lane-start bootstrap check runs. No promotion_evidence_* option is set
# anywhere, which is the condition under test.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p .claude src
printf '# source-control configuration\n\n## babysit_loop_merge\n\nc3-autonomous\n' >.claude/source-control.md
printf 'export const answer = 42;\n' >src/app.ts
git add .claude src
git commit -q -m "chore: seed"
