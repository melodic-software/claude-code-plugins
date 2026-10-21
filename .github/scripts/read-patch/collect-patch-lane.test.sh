#!/usr/bin/env bash
# Tests that collect-patch.sh leaves .lane/, where pr-run-activity-read.yml
# stages the skill's plugin, CI context, scratch directory and prompt, out of
# the patch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-patch.sh"

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  FAILED=1
}
check() {
  if [[ $2 == "$3" ]]; then ok "$1"; else not_ok "$1: expected [$2], got [$3]"; fi
}

tg() { git -C "$R" -c user.name=t -c user.email=t@t.t -c commit.gpgsign=false "$@"; }
new_repo() {
  R="$(mktemp -d "$TMP/repo.XXXXXX")"
  git init -q -b main "$R"
  printf 'one\n' >"$R/edit.txt"
  tg add -A
  tg commit -q -m head
  HEAD_SHA=$(tg rev-parse HEAD)
  PATCH="$TMP/out.$RANDOM/patch.diff"
  mkdir -p "$(dirname "$PATCH")"
  mkdir -p "$R/.lane/plugins/p" "$R/.lane/ci" "$R/.lane/scratch"
  printf 'skill\n' >"$R/.lane/plugins/p/SKILL.md"
  printf '{}\n' >"$R/.lane/ci/context.json"
  printf 'state\n' >"$R/.lane/scratch/notes.txt"
  printf 'Call the Skill tool\n' >"$R/.lane/prompt.md"
}
run_collect() {
  OUT=$(cd "$R" && bash "$COLLECT" "$HEAD_SHA" "$PATCH")
}
field() { sed -n "s/^$1=//p" <<<"$OUT"; }

new_repo
printf 'two\n' >"$R/edit.txt"
run_collect
check "a change beside .lane/ is written" written "$(field state)"
check "the patch holds the change" 1 "$(grep -c '^diff --git a/edit.txt b/edit.txt$' "$PATCH")"
check "the patch holds no .lane/ path" 0 "$(grep -c '\.lane/' "$PATCH" || true)"

new_repo
run_collect
check "a run that changed only .lane/ leaves no patch" empty "$(field state)"
check "no patch file is left" absent "$([[ -e $PATCH ]] && echo present || echo absent)"

exit "$FAILED"
