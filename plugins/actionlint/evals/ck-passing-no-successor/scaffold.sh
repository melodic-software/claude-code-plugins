#!/usr/bin/env bash
# A throwaway clone that declined the actionlint pre-commit entry, so install.mjs verify reports
# `declined` (INFO, setup SKILL.md lines 80-81) and every row of the check can pass.
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q .
git config --local checks.actionlint.actionlint-check.declined true
