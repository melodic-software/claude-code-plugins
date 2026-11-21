#!/usr/bin/env bash
# compare-arms.sh: the two arm patches of a pr-run-plugin-evals.yml compare
# run, each against the default branch tip MAIN_SHA, built from git objects in
# the pull request clone REPO and never from its working tree. Only the
# plugin's skills/, agents/ and evals/ paths the pull request changes since
# its merge base, and only once select-plugins.mjs lets them all through,
# reach a patch; every other file of the plugin stays the default branch's
# (the data-only rule of https://github.com/melodic-software/claude-code-plugins/issues/17854).
#   after   each changed path as the head has it
#   before  each changed skills/ or agents/ path as the merge base has it, and
#           each changed evals/ path as the head has it, so both arms run the
#           same cases
# Reads REPO, MAIN_SHA, HEAD_SHA, PLUGIN (a name) and OUT; writes
# OUT/before/edit.patch and OUT/after/edit.patch (empty when the arm is the
# default branch as is), and merge-base, before-sha256 and after-sha256 to
# GITHUB_OUTPUT (an empty patch has an empty sum).
# Exit codes:
#   0  both patches written
#   1  refused: no changed path, a path select-plugins.mjs refuses, or arms
#      that do not differ
# shellcheck disable=SC2154 # the step env sets REPO, MAIN_SHA, HEAD_SHA, PLUGIN and OUT, and the runner GITHUB_OUTPUT
set -euo pipefail
[[ $MAIN_SHA =~ ^[0-9a-f]{40}$ && $HEAD_SHA =~ ^[0-9a-f]{40}$ ]] || { echo "::error::MAIN_SHA and HEAD_SHA must be full SHAs"; exit 1; }
[[ $PLUGIN =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "::error::PLUGIN must be a plugin directory name"; exit 1; }
here=${BASH_SOURCE[0]%/*}
merge_base=$(git -C "$REPO" merge-base "$MAIN_SHA" "$HEAD_SHA")
mapfile -t files < <(git -C "$REPO" diff --no-renames --name-only "$merge_base" "$HEAD_SHA" -- \
  "plugins/$PLUGIN/skills" "plugins/$PLUGIN/agents" "plugins/$PLUGIN/evals")
if [[ ${#files[@]} -eq 0 ]]; then
  echo "::error::the pull request changes nothing under plugins/$PLUGIN/skills, agents or evals"
  exit 1
fi
printf '%s\n' "${files[@]}" | node "$here/select-plugins.mjs" --repo "$REPO" --base "$merge_base" --head "$HEAD_SHA" >/dev/null || {
  echo "::error::select-plugins.mjs refuses the pull request's change to plugins/$PLUGIN, so no arm runs it beside the credential"
  exit 1
}
index=$(mktemp)
trap 'rm -f "$index"' EXIT
arm_tree() {
  rm -f "$index"
  GIT_INDEX_FILE=$index git -C "$REPO" read-tree "$MAIN_SHA"
  local path from entry
  for path in "${files[@]}"; do
    case $path in
      "plugins/$PLUGIN/evals/"*) from=$HEAD_SHA ;;
      *) from=$1 ;;
    esac
    entry=$(git -C "$REPO" ls-tree "$from" -- "$path")
    if [[ -n $entry ]]; then
      read -r mode _ blob _ <<<"$entry"
      GIT_INDEX_FILE=$index git -C "$REPO" update-index --add --cacheinfo "$mode,$blob,$path"
    else
      GIT_INDEX_FILE=$index git -C "$REPO" update-index --force-remove -- "$path"
    fi
  done
  GIT_INDEX_FILE=$index git -C "$REPO" write-tree
}
before=$(arm_tree "$merge_base")
after=$(arm_tree "$HEAD_SHA")
if [[ $before == "$after" ]]; then
  echo "::error::the pull request changes no skill or agent text, so the two arms would run the same plugin"
  exit 1
fi
main_tree=$(git -C "$REPO" rev-parse "$MAIN_SHA^{tree}")
{
  echo "merge-base=$merge_base"
  for side in before after; do
    mkdir -p "$OUT/$side"
    tree=$before
    [[ $side == after ]] && tree=$after
    git -C "$REPO" diff --binary --no-renames "$main_tree" "$tree" >"$OUT/$side/edit.patch"
    sum=""
    if [[ -s $OUT/$side/edit.patch ]]; then
      sum=$(sha256sum <"$OUT/$side/edit.patch")
      sum=${sum%% *}
    fi
    echo "$side-sha256=$sum"
  done
} >>"$GITHUB_OUTPUT"
echo "compare-arms: ${#files[@]} changed path(s) under plugins/$PLUGIN; merge base $merge_base"
