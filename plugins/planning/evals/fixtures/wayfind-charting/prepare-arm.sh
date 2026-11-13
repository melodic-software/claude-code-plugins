#!/usr/bin/env bash
# Writes one arm of the wayfind-charting suite: a copy of the planning plugin at <ref>, outside any
# repository, whose evals/ holds only this checkout's cases listed in cases.txt and this fixture
# directory. `claude plugin eval` then runs it with --ablation none.
#
#   prepare-arm.sh <ref> <dest> <before|after>
#
# <ref> is a commit of this repository (the before arm pins the PR's merge base). The third
# argument picks the settled-facts map export written the way that arm's skill text keeps facts.
#
# Exit: 0 written; 2 a usage error, or a dest that already exists.
set -euo pipefail

usage() {
  echo "usage: prepare-arm.sh <ref> <dest> <before|after>" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
ref="$1"
dest="$2"
arm="$3"
[[ "$arm" == before || "$arm" == after ]] || usage
if [[ -e "$dest" ]]; then
  echo "prepare-arm.sh: $dest already exists" >&2
  exit 2
fi

parent="$(dirname "$dest")"
if [[ ! -d "$parent" ]] || git -C "$parent" rev-parse --git-dir >/dev/null 2>&1; then
  echo "prepare-arm.sh: $dest must sit in an existing directory outside any git repository" >&2
  exit 2
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin="$(cd "$here/../../.." && pwd)"
repo="$(git -C "$plugin" rev-parse --show-toplevel)"
git -C "$repo" cat-file -e "$ref^{commit}" || usage

mkdir -p "$dest"
git -C "$repo" archive "$ref" plugins/planning | tar -x -C "$dest" --strip-components=2
rm -rf "${dest:?}/evals"
mkdir -p "$dest/evals/fixtures"
cp -R "$here" "$dest/evals/fixtures/wayfind-charting"
cp -R "$here/settled-facts/$arm" "$dest/evals/fixtures/wayfind-charting/settled-facts/current"
while IFS= read -r name; do
  [[ -n "$name" ]] && cp -R "$plugin/evals/$name" "$dest/evals/$name"
done <"$here/cases.txt"

echo "$dest"
