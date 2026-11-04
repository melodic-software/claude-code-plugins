#!/usr/bin/env bash
# A git repository holding the retired pre-commit hook and the user's chained hook (retirements.yaml guardrails-r003).
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
printf '#!/bin/sh\n# guardrails-pre-commit-content-invariants\nexit 0\n' >.git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
printf '#!/bin/sh\n# the earlier pre-commit hook of this clone\nexit 0\n' >.git/hooks/pre-commit.pre-guardrails
chmod +x .git/hooks/pre-commit.pre-guardrails
