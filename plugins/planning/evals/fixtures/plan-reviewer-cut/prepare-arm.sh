#!/usr/bin/env bash
# Writes one arm of the plan-reviewer-cut suite: a copy of the planning plugin at <ref>, outside any
# repository, holding this checkout's plan-reviewer-cut cases. `claude plugin eval` then runs it
# with --ablation none.
#
#   prepare-arm.sh <ref> <dest>
#
# <ref> is a commit of this repository (the before arm pins the PR's merge base).
#
# Exit: 0 written; 2 a usage error, or a dest that already exists.
set -euo pipefail

usage() {
  echo "usage: prepare-arm.sh <ref> <dest>" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
ref="$1"
dest="$2"
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
rm -rf "${dest:?}/evals/results"
mkdir -p "$dest/evals/fixtures"
rm -rf "${dest:?}/evals/fixtures/plan-reviewer-cut" "$dest"/evals/plan-reviewer-cut-*
cp -R "$here" "$dest/evals/fixtures/plan-reviewer-cut"
cp -R "$plugin"/evals/plan-reviewer-cut-* "$dest/evals/"

echo "$dest"
