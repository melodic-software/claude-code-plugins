#!/usr/bin/env bash
# A git repository with prose and no spelling record and no typos config, so the lint concern
# resolves to nothing: the plugin is inert by design.
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf 'A short note with no spelling mistakes.\n' >notes.txt
git add .
git commit -q -m "chore: init"
