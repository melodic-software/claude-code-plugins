#!/usr/bin/env bash
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
