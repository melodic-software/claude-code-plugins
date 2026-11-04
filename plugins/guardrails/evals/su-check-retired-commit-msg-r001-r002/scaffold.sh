#!/usr/bin/env bash
# A git repository holding the hooks the retired install-commit-msg action wrote (retirements.yaml guardrails-r001 and guardrails-r002).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf '# Demo\n' >README.md
git add .
git commit -q -m "chore: init"
# Written after the commit, so no scaffold step runs them, at the literal .git/hooks path
# check-retirements.sh reads, whatever core.hooksPath the sandbox sets.
printf '#!/bin/sh\n# guardrails-commit-msg-convention v1\nexit 0\n' >.git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
printf '#!/bin/sh\n# reads pr_title_pattern\nexit 0\n' >.git/hooks/guardrails-resolve-convention.sh
chmod +x .git/hooks/guardrails-resolve-convention.sh
