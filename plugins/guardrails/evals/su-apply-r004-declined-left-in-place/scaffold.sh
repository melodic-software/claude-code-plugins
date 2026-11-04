#!/usr/bin/env bash
# A git repository holding only the retired content-lib directory (retirements.yaml guardrails-r004).
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
mkdir -p .git/hooks/guardrails-content-lib
printf '#!/bin/sh\n# retired pattern library\n' >.git/hooks/guardrails-content-lib/secret-patterns.sh
chmod +x .git/hooks/guardrails-content-lib/secret-patterns.sh
