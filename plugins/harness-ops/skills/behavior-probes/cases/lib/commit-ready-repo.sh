#!/usr/bin/env bash
# commit-ready-repo.sh <dir>: a repo <dir>/repo with one staged file and nothing committed.
set -euo pipefail
d="$1"
mkdir -p "$d/repo"
cd "$d/repo"
git init -q -b main
git config user.email probe@example.invalid
git config user.name probe
git config commit.gpgsign false
echo a >f
git add f
