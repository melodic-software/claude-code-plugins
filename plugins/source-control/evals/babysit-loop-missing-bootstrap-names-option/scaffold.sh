#!/usr/bin/env bash
# Seeds the workspace as the target checkout: one commit on main whose tracked
# docs/conventions/source-control.yaml adopts the loop lane at c3-autonomous, so the resolved rung
# is merge-capable and the lane-start bootstrap check runs. No promotion_evidence_* option is set
# anywhere, which is the condition under test. An offline origin serves the prompt's PRs #41 and #42
# (fixtures/gh-forge), so no gh call reaches the real gh in the with-arm.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions src
printf 'babysit_loop_merge: c3-autonomous\n' >docs/conventions/source-control.yaml
printf 'export const answer = 42;\n' >src/app.ts
git add docs src
git commit -q -m "chore: seed"
for b in fix/c2-item feat/c3-item; do
  git checkout -q -b "$b" main
  printf '// %s\n' "$b" >>src/app.ts
  git commit -q -am "chore: $b"
done
git checkout -q main
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/gh-forge/install.sh" 41 fix/c2-item main "fix: c2 item" \
  --open --extra-pr 42 feat/c3-item "feat: c3 item"
