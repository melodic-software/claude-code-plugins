#!/usr/bin/env bash
# Writes one arm of the plan-reviewer-cut suite: a copy of the planning plugin at <ref>, outside any
# repository, holding this checkout's plan-reviewer-cut cases. `claude plugin eval` then runs it
# with --ablation none.
#
#   prepare-arm.sh <ref> <dest> [--degrade-reviewer]
#
# <ref> is a commit of this repository (the before arm pins the PR's merge base). With
# --degrade-reviewer, the copy's plan-reviewer agent keeps its frontmatter and takes its body from
# plan-reviewer-degraded-body.md.txt, and the dispatch prompt (skills/plan/context/plan-reviewer.md)
# is replaced by plan-reviewer-degraded-prompt.md.txt: the suite's negative control. Both are
# replaced because the review axes and the report format live in the dispatch prompt.
#
# Exit: 0 written; 2 a usage error, or a dest that already exists.
set -euo pipefail

usage() {
  echo "usage: prepare-arm.sh <ref> <dest> [--degrade-reviewer]" >&2
  exit 2
}

[[ $# -ge 2 && $# -le 3 ]] || usage
ref="$1"
dest="$2"
degrade="${3:-}"
[[ -z "$degrade" || "$degrade" == "--degrade-reviewer" ]] || usage
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

if [[ -n "$degrade" ]]; then
  agent="$dest/agents/plan-reviewer.md"
  frontmatter="$(awk 'NR == 1 || !done { print } NR > 1 && /^---$/ { done = 1 }' "$agent")"
  printf '%s\n\n' "$frontmatter" >"$agent"
  cat "$here/plan-reviewer-degraded-body.md.txt" >>"$agent"
  cp "$here/plan-reviewer-degraded-prompt.md.txt" "$dest/skills/plan/context/plan-reviewer.md"
fi

echo "$dest"
