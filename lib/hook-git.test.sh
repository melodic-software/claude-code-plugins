#!/usr/bin/env bash
# test-scope: lib/hook-utils.sh lib/resolve-convention-pattern.sh
# test-scope: plugins/eol-normalizer/hooks/normalize-eol.sh plugins/source-control/hooks/worktree-remove-gate.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES GIT_CONFIG CLAUDE_PROJECT_DIR

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS="$LIB/../plugins"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
T="$(cd -P "$T" && pwd)"

FAILED=0
PASSED=0
pass() {
  PASSED=$((PASSED + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1" >&2
}
expect() {
  local label="$1"
  shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}

command -v git >/dev/null 2>&1 || {
  echo "SKIP: git not on PATH"
  exit 0
}

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOOK_TELEMETRY_SINK=
g() { git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

R="$T/repo"
mkdir -p "$R/docs/conventions" "$R/.work"
printf '.work/\nignored.txt\n' >"$R/.gitignore"
printf 'a\n' >"$R/a.txt"
printf 'subject_pattern: "^feat"\n' >"$R/docs/conventions/source-control.yaml"
g init -q "$R"
g -C "$R" add .
g -C "$R" commit -q -m init
g -C "$R" worktree add -q -b wt "$T/wt"
printf 'x\n' >"$T/wt/untracked.txt"

MARK="$T/fsmonitor-ran"
printf '#!/bin/sh\ntouch "%s"\n' "$MARK" >"$T/fsmonitor.sh"
chmod +x "$T/fsmonitor.sh"
g -C "$R" config core.fsmonitor "$T/fsmonitor.sh"

git -C "$R" check-ignore -q -- a.txt >/dev/null 2>&1
if [[ -e "$MARK" ]]; then
  pass "fixture: a plain git check-ignore runs the planted fsmonitor"
else
  fail "fixture: the planted fsmonitor never fires, so no case below proves anything"
fi

not_run() {
  if [[ -e "$MARK" ]]; then fail "$1: ran the repository's core.fsmonitor"; else pass "$1: core.fsmonitor never runs"; fi
  rm -f "$MARK"
}
rm -f "$MARK"

sh "$LIB/resolve-convention-pattern.sh" "$R" subject_pattern >/dev/null 2>&1
not_run "resolve-convention-pattern tracked-file check"

bash -c 'source "$1/hook-utils.sh" && source "$2" && normalize_eol_resolve_attrs "$3" a.txt' _ \
  "$PLUGINS/eol-normalizer/hooks" "$PLUGINS/eol-normalizer/hooks/normalize-eol.sh" "$R"
not_run "normalize-eol check-attr"

out=$(jq -n --arg p "$T/wt" '{worktree_path:$p,session_id:"s"}' |
  bash "$PLUGINS/source-control/hooks/worktree-remove-gate.sh" 2>&1)
rc=$?
not_run "worktree-remove-gate status"
refused=no
[[ "$out" == *"uncommitted or untracked"* ]] && refused=yes
expect "worktree-remove-gate: still refuses a worktree with an untracked file (rc $rc: $out)" test "$rc:$refused" = "1:yes"

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
((FAILED == 0))
