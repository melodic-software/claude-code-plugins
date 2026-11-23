#!/usr/bin/env bash
# run-prepare.sh: the workflow step around prepare.sh, run from the root of the
# PR head checkout by each job of a resolve-conflicts round that merges:
# pr-unblock.yml's resolve-conflicts-select, the read runner before the model,
# and the write runner's apply-patch before the push. Each stages what it runs
# from BIN out of the base, with their SHA-256s, through stage-bin.sh.
#
# 1. Checks prepare.sh and the version-bump script against their SHA-256s.
# 2. Runs prepare.sh with workflow commands stopped, since git's output names
#    head files.
# 3. Takes only prepare.sh's known keys, once each, and a valid merge-state and
#    escalation-reason pair; a clean or conflicted merge must name its conflict
#    tree, and an escalation none.
# 4. With EXPECT_STATE set (a later job of the round), fails unless the merge
#    reaches the select job's state and conflict tree: three merges of one
#    head and one pinned base must agree, or nothing is resolved or pushed.
#
# Environment: BIN (holding prepare.sh and resolve-version-bump-conflict.sh),
# OUT (prepare.sh's out-dir), PREPARE_SHA256, BUMP_SHA256, HEAD_SHA, BASE_SHA,
# GITHUB_OUTPUT, and the lanes bot identity and LOOP_NO_PROGRESS prepare.sh
# reads; optional EXPECT_STATE and EXPECT_TREE.
#
# Outputs (step outputs, https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#setting-an-output-parameter):
# merge-state, escalation-reason, conflict-tree, skip-reason
# (awaiting-human on an escalation), and conflict-paths: prepare.sh's unmerged
# paths as one JSON array line (needs jq), empty when there are none, when the
# line passes 16,384 characters, or when a path is not UTF-8. Exit 1 on a hash
# mismatch, a prepare.sh failure, malformed output, or a merge that does not
# reach the expected state and tree.
set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}
check() {
  local sum
  sum=$(sha256sum <"$1")
  [[ ${sum%% *} == "$2" ]] || fail "$1 does not match the SHA-256 recorded when it was copied from the base"
}
for v in BIN OUT PREPARE_SHA256 BUMP_SHA256 HEAD_SHA BASE_SHA GITHUB_OUTPUT; do
  [[ -n ${!v:-} ]] || fail "$v is not set"
done
BIN=${BIN:?} OUT=${OUT:?} HEAD_SHA=${HEAD_SHA:?} BASE_SHA=${BASE_SHA:?} GITHUB_OUTPUT=${GITHUB_OUTPUT:?}
check "$BIN/prepare.sh" "${PREPARE_SHA256:?}"
check "$BIN/resolve-version-bump-conflict.sh" "${BUMP_SHA256:?}"

token=$(openssl rand -hex 16)
echo "::stop-commands::$token"
rc=0
result=$(bash "$BIN/prepare.sh" "$HEAD_SHA" "$BASE_SHA" "$BIN/resolve-version-bump-conflict.sh" "$OUT") || rc=$?
echo "::$token::"
((rc == 0)) || fail "prepare.sh exited $rc"

state="" reason="" tree="" seen=""
while IFS='=' read -r key value; do
  [[ $seen != *" $key "* ]] || fail "prepare.sh printed $key twice"
  seen+=" $key "
  case $key in
    merge-state) state=$value ;;
    escalation-reason) reason=$value ;;
    conflict-tree) tree=$value ;;
    *) fail "prepare.sh printed an unknown key" ;;
  esac
done <<<"$result"

skip=""
case $state:$reason in
  clean: | conflicted:)
    [[ $tree =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || fail "prepare.sh printed no conflict tree"
    ;;
  escalate:protected-path-conflict | escalate:repeat-cap | escalate:unresolved-conflict)
    [[ -z $tree ]] || fail "prepare.sh printed a conflict tree beside an escalation"
    skip=awaiting-human
    ;;
  *) fail "prepare.sh printed no valid merge-state and escalation-reason" ;;
esac

if [[ -n ${EXPECT_STATE:-} ]]; then
  if [[ $state != "$EXPECT_STATE" || $tree != "${EXPECT_TREE:-}" ]]; then
    fail "the merge reached ${state:-nothing} at ${tree:-no tree}, not the select job's $EXPECT_STATE at ${EXPECT_TREE:-no tree}; nothing is resolved or pushed"
  fi
fi

paths=""
if [[ -s $OUT/unmerged-paths ]]; then
  paths=$(jq -Rsc 'split("\u0000") | map(select(. != ""))' <"$OUT/unmerged-paths")
fi
if ((${#paths} > 16384)) || [[ $paths == *$'\xef\xbf\xbd'* ]]; then
  paths=""
fi

{
  echo "merge-state=$state"
  echo "escalation-reason=$reason"
  echo "conflict-tree=$tree"
  echo "skip-reason=$skip"
  echo "conflict-paths=$paths"
} >>"$GITHUB_OUTPUT"
echo "merge-state=$state escalation-reason=$reason conflict-tree=$tree"
