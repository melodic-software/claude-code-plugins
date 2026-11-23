#!/usr/bin/env bash
# shellcheck disable=SC2154 # the step env sets IN, RELEASE, BASE_SHA and REPO_DIR, and the runner GITHUB_OUTPUT
set -eo pipefail

lane="$(dirname "${BASH_SOURCE[0]}")/upstream-apply-changelog.mjs"
[[ -f "$IN/plan.json" ]] || { echo "::error::the apply-changelog job left no ci-plan.json"; exit 1; }
node "$lane" plan-files
: >"$IN/diffs.txt"
count=0
if [[ -s "$IN/heads.txt" ]] && [[ ! -f "$IN/branches.bundle" ]]; then
  echo "::error::the plan names branches and the apply-changelog job left no bundle"
  exit 1
fi
if [[ -s "$IN/heads.txt" ]]; then
  git -C "$REPO_DIR" bundle verify --quiet "$IN/branches.bundle" >/dev/null 2>&1 || { echo "::error::the branches bundle does not verify against the base"; exit 1; }
  mapfile -t have < <(git -C "$REPO_DIR" bundle list-heads "$IN/branches.bundle" 2>/dev/null | cut -d' ' -f1 | sort -u)
  mapfile -t want < <(sort -u "$IN/heads.txt")
  missing=$(comm -13 <(printf '%s\n' "${have[@]}") <(printf '%s\n' "${want[@]}") | grep -c . || true)
  if [[ "$missing" != 0 ]]; then
    echo "::error::$missing of ${#want[@]} planned heads are not heads of the bundle"
    exit 1
  fi
  while read -r head; do
    [[ $head =~ ^[0-9a-f]{40}$ ]] || exit 1
    git -C "$REPO_DIR" fetch --quiet --no-tags "$IN/branches.bundle" "$head:refs/scan/$head" >/dev/null 2>&1 || { echo "::error::a planned head did not fetch from the bundle"; exit 1; }
    numstat=$(git -C "$REPO_DIR" diff --numstat --no-renames "$BASE_SHA" "$head")
    if grep -q $'^-\t-\t' <<<"$numstat"; then
      echo "::error::a planned branch changes a binary file; only text is published"
      exit 1
    fi
  done <"$IN/heads.txt"
fi
node "$lane" scan
while read -r head; do
  git -C "$REPO_DIR" diff --no-renames --binary "$BASE_SHA" "$head" >>"$IN/diffs.txt"
  count=$((count + 1))
done <"$IN/heads.txt"
rm -rf "${OUT:?}"
mkdir -p "$OUT"
cp "$IN/plan.json" "$OUT/plan.json"
synthetic='[]'
if ((count)); then
  synthetic=$(node "$lane" synthetic) || { echo "$synthetic"; echo "::error::the planned heads did not bundle"; exit 1; }
fi
{ echo "branches=$count"; echo "synthetic=$synthetic"; } >>"$GITHUB_OUTPUT"
