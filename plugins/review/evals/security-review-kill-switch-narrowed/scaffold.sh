#!/usr/bin/env bash
# main's kill switch lets a lane run when its variable reads "false" or "0".
# The branch drops "0", so only "false" lets a lane run: every value that
# stopped a lane still does, and one that let it run now stops it.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p .github/actions/check-kill-switch

cat >.github/actions/check-kill-switch/decide.mjs <<'JS'
// Whether a lane may run. Only "false" or "0" lets it run, so an unset, empty
// or unreadable variable stops every lane.
export function decide(value) {
  if (value === "false" || value === "0") return { proceed: true };
  return { proceed: false, reason: value === "" || value == null ? "unset" : `set to ${value}` };
}
JS

cat >.github/actions/check-kill-switch/action.yml <<'YAML'
name: check-kill-switch
description: Stop the lane unless LANES_DISABLED reads false.
inputs:
  value:
    required: true
outputs:
  proceed:
    value: ${{ steps.decide.outputs.proceed }}
runs:
  using: composite
  steps:
    - id: decide
      shell: bash
      env:
        VALUE: ${{ inputs.value }}
      run: node --input-type=module -e 'import { decide } from "${{ github.action_path }}/decide.mjs"; const d = decide(process.env.VALUE); console.log(`proceed=${d.proceed}`);' >>"$GITHUB_OUTPUT"
YAML

git add .
git commit -q -m "feat: kill switch for the lanes"

git checkout -q -b fix/kill-switch-only-false
cat >.github/actions/check-kill-switch/decide.mjs <<'JS'
// Whether a lane may run. Only the literal "false" lets it run, so an unset,
// empty or unreadable variable stops every lane.
export function decide(value) {
  if (value === "false") return { proceed: true };
  return { proceed: false, reason: value === "" || value == null ? "unset" : `set to ${value}` };
}
JS

git add .
git commit -q -m "fix(kill-switch): only false lets a lane run"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
