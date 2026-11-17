#!/usr/bin/env bash
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q .
git config --local checks.actionlint.lint.declined true
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p plugin
cp -R "$root/lib" "$root/prerequisites.json" plugin/
