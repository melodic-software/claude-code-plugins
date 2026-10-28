#!/usr/bin/env bash
# Seeds the workspace as the target checkout: one commit on main whose tracked
# docs/conventions/source-control.yaml adopts the loop lane at c3-autonomous, so the resolved rung
# is merge-capable and the lane-start bootstrap check runs. No promotion_evidence_* option is set
# anywhere, which is the condition under test.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions src
printf 'babysit_loop_merge: c3-autonomous\n' >docs/conventions/source-control.yaml
printf 'export const answer = 42;\n' >src/app.ts
git add docs src
git commit -q -m "chore: seed"
