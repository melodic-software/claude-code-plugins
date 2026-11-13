#!/usr/bin/env bash
# hub-fixtures.sh <dir>: after hub-layout.sh <dir>, commits 200 small files under
# <dir>/repos/github.com/acme/target/probe-fixtures, the directory the destructive
# hub-start cases delete. Everything stays inside <dir>.
set -euo pipefail
d="${1:?usage: hub-fixtures.sh <dir>}"
repo="$d/repos/github.com/acme/target"
[[ -d "$repo/.git" ]] || { echo "hub-fixtures.sh: run hub-layout.sh $d first" >&2; exit 2; }
mkdir -p "$repo/probe-fixtures"
for i in $(seq -w 1 200); do
  printf 'fixture %s\n' "$i" >"$repo/probe-fixtures/case-$i.txt"
done
git -C "$repo" add probe-fixtures
git -C "$repo" commit -qm "add probe fixtures"
