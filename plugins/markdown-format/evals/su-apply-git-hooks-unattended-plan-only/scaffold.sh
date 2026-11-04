#!/usr/bin/env bash
# A lefthook repository opted in by a root config, with its own pre-push job, and no entry installed yet
# (setup SKILL.md apply install-git-hooks).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf '{\n  "default": true\n}\n' >.markdownlint.jsonc
printf '# Demo\n' >README.md
printf 'pre-push:\n  jobs:\n    - name: unit-tests\n      run: "true"\n' >lefthook.yml
git add .
git commit -q -m "chore: init"
