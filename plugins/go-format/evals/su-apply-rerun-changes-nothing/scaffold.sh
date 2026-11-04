#!/usr/bin/env bash
# A git repository where every check step passes or is INFO on a host with node, jq and goimports:
# this clone declined the pre-commit entry, so verify reports declined (setup SKILL.md check step 9).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.go-format.goimports-format.declined true
printf 'module example.invalid/demo\n\ngo 1.22\n' >go.mod
printf 'package main\n\nfunc main() {}\n' >main.go
git add .
git commit -q -m "chore: init"
