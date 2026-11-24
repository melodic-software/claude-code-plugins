#!/usr/bin/env bash
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

export PREFLIGHT_UNAME=Linux
unset PREFLIGHT_UID

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/preflight.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

run() {
  local fx="$1" cfg="$2"
  shift 2
  PREFLIGHT_FIXTURE_DIR="$fx" CLAUDE_CONFIG_DIR="$cfg" bash "$SCRIPT" "$@"
}

run_home() {
  local home="$1" fx="$2" cfg="$3"
  shift 3
  HOME="$home" PREFLIGHT_FIXTURE_DIR="$fx" CLAUDE_CONFIG_DIR="$cfg" bash "$SCRIPT" "$@"
}

# write_settings <config-dir> <allow-json-array> [dir ...]
# additionalDirectories entries are passed as plain path strings and JSON-encoded
# by jq (--args), so backslash-bearing Windows paths never break the JSON.
write_settings() {
  local cfg="$1" allow="$2"
  shift 2
  mkdir -p "$cfg"
  jq -n --argjson a "$allow" \
    '{permissions:{allow:$a, additionalDirectories:$ARGS.positional}}' \
    --args "$@" >"$cfg/settings.json"
}

# commit_empty <repo> — a commit so `worktree add` has a HEAD to detach from.
commit_empty() {
  git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -F - --cleanup=verbatim <<'MSG'
init
MSG
}

FULL_ALLOW='["Bash(git add *)","Bash(git commit *)","Bash(git push)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"]'

# Runtime-assembled Windows path (no contiguous path literal in source).
# shellcheck disable=SC1003  # BS is a literal single backslash, not a quote escape
BS='\'
SL='/'
WIN_ROOT="D:${BS}repos${BS}.worktrees"
POSIX_CHILD="${SL}d${SL}repos${SL}.worktrees${SL}495-x"

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

real_bash=$(command -v bash)
empty_path_dir="$TEST_TMPDIR/empty-path"
mkdir -p "$empty_path_dir"
rc=0
err_out=$(PATH="$empty_path_dir" "$real_bash" "$SCRIPT" 2>&1) || rc=$?
assert_exit "exit 2 when jq missing" 2 "$rc"
assert_contains "jq required message" "$err_out" "jq required"

REPO="$TEST_TMPDIR/clean-repo"
mkdir -p "$REPO"
git init -q "$REPO"
CFG3="$TEST_TMPDIR/cfg3"
write_settings "$CFG3" "$FULL_ALLOW" "$WIN_ROOT"
rc=0
OUT=$(run "$REPO" "$CFG3" --worktree-root "$POSIX_CHILD") || rc=$?
assert_exit "clean run exits 0" 0 "$rc"
assert_contains "clean run reports OK" "$OUT" "PREFLIGHT: OK"
assert_not_contains "clean run has no GAP" "$OUT" "GAP"
assert_eq "clean run gap count 0" "0" "$(run "$REPO" "$CFG3" --count --worktree-root "$POSIX_CHILD")"

NONREPO="$TEST_TMPDIR/not-a-repo"
mkdir -p "$NONREPO"
OUT=$(run "$NONREPO" "$CFG3" --worktree-root "$POSIX_CHILD")
assert_contains "non-repo emits NOTE (a)" "$OUT" "NOTE (a)"
assert_contains "non-repo names the dir" "$OUT" "is not a git repository"
assert_eq "non-repo is a note, not a gap" "0" "$(run "$NONREPO" "$CFG3" --count --worktree-root "$POSIX_CHILD")"

CFG5="$TEST_TMPDIR/cfg5"
write_settings "$CFG5" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
OUT=$(run "$REPO" "$CFG5" --worktree-root "$POSIX_CHILD")
assert_contains "missing verb emits GAP (b)" "$OUT" "GAP (b)"
assert_contains "GAP names the missing verb" "$OUT" "'gh pr create'"
assert_contains "GAP points at the standards floor" "$OUT" "components/claude-permissions"
assert_not_contains "present verbs not flagged" "$OUT" "'git commit'"
assert_eq "one missing verb → one gap" "1" "$(run "$REPO" "$CFG5" --count --worktree-root "$POSIX_CHILD")"

CFG5B="$TEST_TMPDIR/cfg5b"
write_settings "$CFG5B" \
  '["Bash(git commit *)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
OUT=$(run "$REPO" "$CFG5B" --worktree-root "$POSIX_CHILD")
assert_contains "missing git add emits a gap" "$OUT" "'git add'"
assert_eq "git add is the only missing verb → one gap" "1" "$(run "$REPO" "$CFG5B" --count --worktree-root "$POSIX_CHILD")"

CFG6="$TEST_TMPDIR/cfg6"
write_settings "$CFG6" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","PowerShell(gh pr create *)","Bash(gh issue comment:*)"]'
assert_eq "all spelling variants recognized → 0 (b) gaps" "0" "$(run "$REPO" "$CFG6" --count)"
OUT=$(run "$REPO" "$CFG6")
assert_not_contains "spelling variants leave no (b) gap" "$OUT" "GAP (b)"

CFG7="$TEST_TMPDIR/cfg7"
write_settings "$CFG7" \
  '["Bash(git add *)","Bash(git commit-tree *)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"]'
OUT=$(run "$REPO" "$CFG7" --worktree-root "$POSIX_CHILD")
assert_contains "commit-tree does not cover commit" "$OUT" "'git commit'"

CFG7B="$TEST_TMPDIR/cfg7b"
write_settings "$CFG7B" \
  '["Bash(git add *)","Bash(git commit --amend)","Bash(git push --force-with-lease *)","Bash(gh pr create *)","Bash(gh issue comment *)"]'
OUT=$(run "$REPO" "$CFG7B")
assert_contains "flag-specific commit rule leaves git commit a gap" "$OUT" "'git commit'"
assert_not_contains "git push is not probed" "$OUT" "'git push'"
assert_not_contains "the open gh pr create rule is not a gap" "$OUT" "'gh pr create'"
assert_eq "one flag-masked probed verb → one (b) gap" "1" "$(run "$REPO" "$CFG7B" --count)"

CFG7C="$TEST_TMPDIR/cfg7c"
write_settings "$CFG7C" \
  '["Bash(git add *)","Bash(git commit)","Bash(gh pr create *)","Bash(gh issue comment *)"]'
OUT=$(run "$REPO" "$CFG7C")
assert_contains "bare-only commit is still a gap" "$OUT" "'git commit'"
assert_contains "gap names the bare-exact-only case" "$OUT" "bare-exact allow rule"
assert_contains "gap points at the open-glob remedy" "$OUT" "Grant the open glob"
assert_not_contains "bare-only commit not the generic missing-allow message" "$OUT" "no Bash()/PowerShell() allow rule covers 'git commit'"
assert_eq "bare-only allow → one gap" "1" "$(run "$REPO" "$CFG7C" --count)"

CFG8="$TEST_TMPDIR/cfg8"
write_settings "$CFG8" "$FULL_ALLOW" "/some/other/root"
OUT=$(run "$REPO" "$CFG8" --worktree-root "$POSIX_CHILD")
assert_contains "uncovered root emits GAP (c)" "$OUT" "GAP (c)"
assert_contains "GAP (c) names additionalDirectories" "$OUT" "additionalDirectories"
assert_eq "uncovered root → one gap" "1" "$(run "$REPO" "$CFG8" --count --worktree-root "$POSIX_CHILD")"

assert_eq "Windows-form entry covers POSIX-form child" "0" "$(run "$REPO" "$CFG3" --count --worktree-root "$POSIX_CHILD")"

CFG9B="$TEST_TMPDIR/cfg9b"
write_settings "$CFG9B" "$FULL_ALLOW" "${SL}d${SL}repos${SL}.worktrees"
assert_eq "POSIX-form entry covers a Windows-form probed root" "0" \
  "$(run "$REPO" "$CFG9B" --count --worktree-root "${WIN_ROOT}${BS}495-x")"

OUT=$(run "$REPO" "$CFG3")
assert_contains "no root arg emits NOTE (c)" "$OUT" "NOTE (c)"
assert_contains "NOTE (c) explains it was not checked" "$OUT" "not checked"
assert_eq "no root arg is a note, not a gap" "0" "$(run "$REPO" "$CFG3" --count)"

REPO2="$TEST_TMPDIR/proj-local"
mkdir -p "$REPO2"
git init -q "$REPO2"
PROJ="$(git -C "$REPO2" rev-parse --show-toplevel)"
mkdir -p "$PROJ/.claude"
CFG11="$TEST_TMPDIR/cfg11"
write_settings "$CFG11" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$PROJ/.claude/settings.local.json"
assert_eq "interactive path reads settings.local.json" "0" "$(run "$REPO2" "$CFG11" --count)"

CNT=$(run "$NONREPO" "$CFG8" --count --worktree-root "$POSIX_CHILD")
assert_eq "count of the one (c) gap (note (a) excluded)" "1" "$CNT"

MAINCO="$TEST_TMPDIR/main-checkout"
git init -q "$MAINCO"
MAINTOP="$(git -C "$MAINCO" rev-parse --show-toplevel)"
mkdir -p "$MAINTOP/.claude"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$MAINTOP/.claude/settings.json"
WORKER="$TEST_TMPDIR/worker-worktree"
git init -q "$WORKER"
CFG13="$TEST_TMPDIR/cfg13"
write_settings "$CFG13" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
assert_eq "main-checkout grant masks the gap without --project-root" "0" "$(run "$MAINCO" "$CFG13" --count --worktree-root "$POSIX_CHILD")"
OUT=$(run "$MAINCO" "$CFG13" --project-root "$WORKER" --worktree-root "$POSIX_CHILD")
assert_contains "--project-root surfaces the worker-side gap" "$OUT" "'gh pr create'"
assert_eq "worker-side gap counted under --project-root" "1" "$(run "$MAINCO" "$CFG13" --project-root "$WORKER" --count --worktree-root "$POSIX_CHILD")"

write_deny() {
  local cfg="$1" allow="$2" deny="$3"
  mkdir -p "$cfg"
  jq -n --argjson a "$allow" --argjson d "$deny" \
    '{permissions:{allow:$a, deny:$d}}' >"$cfg/settings.json"
}

CFG14="$TEST_TMPDIR/cfg14"
write_deny "$CFG14" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"]' \
  '["Bash(git commit *)"]'
OUT=$(run "$REPO" "$CFG14")
assert_contains "allowed-but-denied verb is a gap" "$OUT" "'git commit'"
assert_contains "denied gap has the distinct DENIED message" "$OUT" "is DENIED"
assert_not_contains "denied verb not reported as a missing-allow gap" "$OUT" "no Bash()/PowerShell() allow rule covers 'git commit'"
assert_eq "allow+deny same verb → exactly one gap" "1" "$(run "$REPO" "$CFG14" --count)"

CFG15="$TEST_TMPDIR/cfg15"
write_deny "$CFG15" \
  '["Bash(git commit *)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"]' \
  '["Bash(git add)"]'
OUT=$(run "$REPO" "$CFG15")
assert_contains "deny-only verb is a gap" "$OUT" "'git add'"
assert_contains "deny-only gap has the DENIED message" "$OUT" "is DENIED"
assert_eq "deny-only verb → exactly one gap" "1" "$(run "$REPO" "$CFG15" --count)"

# Since Claude Code v2.1.211, "don't ask again" approvals save to the MAIN
# checkout's settings.local.json and apply in every worktree of the repository —
# so a grant there is real coverage for a fresh worker, and the autonomous path
# reads it instead of dropping it.
REPO3="$TEST_TMPDIR/local-mask"
git init -q "$REPO3"
PROJ3="$(git -C "$REPO3" rev-parse --show-toplevel)"
mkdir -p "$PROJ3/.claude"
CFG16="$TEST_TMPDIR/cfg16"
write_settings "$CFG16" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$PROJ3/.claude/settings.local.json"
assert_eq "interactive path reads local grant → no gap" "0" "$(run "$REPO3" "$CFG16" --count)"
OUT=$(run "$REPO3" "$CFG16" --worktree-root "$POSIX_CHILD")
assert_contains "header states the main-local inclusion basis" "$OUT" \
  "includes this main checkout's settings.local.json: where approvals save at the repository root"
assert_eq "autonomous path reads the main checkout's local grant → no gap" "0" "$(run "$REPO3" "$CFG16" --count --worktree-root "$POSIX_CHILD")"

commit_empty "$REPO3"
WT16="$TEST_TMPDIR/local-mask-wt"
git -C "$REPO3" worktree add -q --detach "$WT16"
assert_eq "main checkout's local grant covers from a worktree cwd → no gap" "0" "$(run "$WT16" "$CFG16" --count --worktree-root "$POSIX_CHILD")"
rm "$PROJ3/.claude/settings.local.json"
mkdir -p "$WT16/.claude"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$WT16/.claude/settings.local.json"
assert_eq "interactive path in the worktree reads its own local → no gap" "0" "$(run "$WT16" "$CFG16" --count)"
OUT=$(run "$WT16" "$CFG16" --worktree-root "$POSIX_CHILD")
assert_contains "autonomous path drops the worktree's own local → gap surfaces" "$OUT" "'gh pr create'"
assert_contains "header notes the worktree-local exclusion" "$OUT" "excludes this worktree's own local file"
assert_eq "worktree-local-only grant → one gap" "1" "$(run "$WT16" "$CFG16" --count --worktree-root "$POSIX_CHILD")"

SEPCO="$TEST_TMPDIR/sep-main"
git init -q --separate-git-dir "$TEST_TMPDIR/sep-gitdir" "$SEPCO"
SEPTOP="$(git -C "$SEPCO" rev-parse --show-toplevel)"
mkdir -p "$SEPTOP/.claude"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$SEPTOP/.claude/settings.local.json"
assert_eq "separate-git-dir main checkout's local grant counts → no gap" "0" "$(run "$SEPCO" "$CFG16" --count --worktree-root "$POSIX_CHILD")"

CFG16D="$TEST_TMPDIR/cfg16d"
write_settings "$CFG16D" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
jq -n '{permissions:{deny:["Bash(git commit *)"]}}' >"$PROJ3/.claude/settings.local.json"
OUT=$(run "$WT16" "$CFG16D" --worktree-root "$POSIX_CHILD")
assert_contains "main-local deny reaches a worktree run" "$OUT" "'git commit'"
assert_contains "main-local deny carries the DENIED message" "$OUT" "is DENIED"
assert_eq "main-local deny → exactly one gap" "1" "$(run "$WT16" "$CFG16D" --count --worktree-root "$POSIX_CHILD")"

plant_main_deny() {
  mkdir -p "$1/.claude"
  jq -n '{permissions:{deny:["Bash(git commit *)"]}}' >"$1/.claude/settings.local.json"
}
CFGRES="$TEST_TMPDIR/cfg-res"
mkdir -p "$CFGRES"
MSYS_NO_PATHCONV=1 jq -n '{permissions:{allow:["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"],additionalDirectories:["/"]}}' >"$CFGRES/settings.json"
RESROOT="$TEST_TMPDIR/res-wtroot"

CONV="$TEST_TMPDIR/res-conv"
git init -q "$CONV"
commit_empty "$CONV"
plant_main_deny "$CONV"
git -C "$CONV" worktree add -q --detach "$TEST_TMPDIR/res-conv-wt"
OUT=$(run "$TEST_TMPDIR/res-conv-wt" "$CFGRES" --worktree-root "$RESROOT")
assert_contains "conventional worktree reports the main-local deny" "$OUT" "is DENIED"
assert_not_contains "conventional worktree is not INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_eq "conventional worktree → one gap" "1" "$(run "$TEST_TMPDIR/res-conv-wt" "$CFGRES" --count --worktree-root "$RESROOT")"

# A submodule's common dir is <super>/.git/modules/<name>, which no parent-of-.git
# arithmetic can invert. Git records the working tree in that dir's core.worktree,
# which is what makes the shape resolvable at all.
SUPER="$TEST_TMPDIR/res-super"
SUBSRC="$TEST_TMPDIR/res-subsrc"
git init -q "$SUPER"
commit_empty "$SUPER"
git init -q "$SUBSRC"
commit_empty "$SUBSRC"
git -C "$SUPER" -c protocol.file.allow=always -c user.name=t -c user.email=t@t \
  submodule add -q "$SUBSRC" sub 2>/dev/null
git -C "$SUPER" -c user.name=t -c user.email=t@t commit -q -F - --cleanup=verbatim <<'MSG'
add submodule
MSG
plant_main_deny "$SUPER/sub"
git -C "$SUPER/sub" worktree add -q --detach "$TEST_TMPDIR/res-sub-wt"
OUT=$(run "$TEST_TMPDIR/res-sub-wt" "$CFGRES" --worktree-root "$RESROOT")
assert_contains "submodule worktree reports the main-local deny" "$OUT" "is DENIED"
# The header prints git's own spelling of the toplevel, which on Windows is the
# native "C:/…" form rather than the shell's "/tmp/…" — compare against git.
assert_contains "submodule worktree names the submodule checkout" "$OUT" \
  "$(git -C "$SUPER/sub" rev-parse --show-toplevel | tr -d '\r')"
assert_not_contains "submodule worktree is not INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_eq "submodule worktree → one gap" "1" "$(run "$TEST_TMPDIR/res-sub-wt" "$CFGRES" --count --worktree-root "$RESROOT")"

# A config may hold core.worktree only via an include directive; `git config -f`
# never processes includes, so the resolution must read with GIT_DIR context.
SUBGITDIR="$(git -C "$SUPER/sub" rev-parse --git-common-dir | tr -d '\r')"
INCWT="$(git config -f "$SUBGITDIR/config" --get core.worktree | tr -d '\r')"
git config -f "$SUBGITDIR/config" --unset core.worktree
printf '[core]\n\tworktree = %s\n' "$INCWT" >"$SUBGITDIR/worktree.inc"
printf '[include]\n\tpath = worktree.inc\n' >>"$SUBGITDIR/config"
OUT=$(run "$TEST_TMPDIR/res-sub-wt" "$CFGRES" --worktree-root "$RESROOT")
assert_contains "include-defined core.worktree still reports the deny" "$OUT" "is DENIED"
assert_not_contains "include-defined core.worktree is not INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"

# --separate-git-dir under a name that is not "<something>/.git" leaves the main
# working tree genuinely unrecoverable (git records no back-pointer to it). The
# planted deny therefore cannot be read — so the run must say the layer is unread
# instead of reporting a clean bill of health.
SEP2="$TEST_TMPDIR/res-sep2"
git init -q --separate-git-dir "$TEST_TMPDIR/res-sep2-gitdir" "$SEP2"
commit_empty "$SEP2"
plant_main_deny "$SEP2"
git -C "$SEP2" worktree add -q --detach "$TEST_TMPDIR/res-sep2-wt"
OUT=$(run "$TEST_TMPDIR/res-sep2-wt" "$CFGRES" --worktree-root "$RESROOT")
assert_contains "unresolvable spelling reports the layer as unread" "$OUT" "UNREAD LAYER"
assert_contains "unresolvable spelling summary is INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_not_contains "unresolvable spelling never claims OK" "$OUT" "PREFLIGHT: OK"
assert_not_contains "unresolvable spelling names no main checkout" "$OUT" "includes the main checkout's settings.local.json ('"
assert_exit "unresolvable spelling still exits 0 (report-only)" 0 "$(
  run "$TEST_TMPDIR/res-sep2-wt" "$CFGRES" --worktree-root "$RESROOT" >/dev/null
  echo $?
)"
assert_eq "unresolvable spelling leaves the gap count untouched" "0" "$(run "$TEST_TMPDIR/res-sep2-wt" "$CFGRES" --count --worktree-root "$RESROOT")"

OUT=$(run "$TEST_TMPDIR/res-sep2-wt" "$CFGRES")
assert_contains "interactive path reports the unread layer" "$OUT" "UNREAD LAYER"
assert_contains "interactive path summary is INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_not_contains "interactive path never claims OK" "$OUT" "PREFLIGHT: OK"

git clone -q --bare "$CONV" "$TEST_TMPDIR/res-bare.git" 2>/dev/null
git -C "$TEST_TMPDIR/res-bare.git" worktree add -q --detach "$TEST_TMPDIR/res-bare-wt"
OUT=$(run "$TEST_TMPDIR/res-bare-wt" "$CFGRES" --worktree-root "$RESROOT")
assert_contains "bare repo's worktree reports OK" "$OUT" "PREFLIGHT: OK"
assert_not_contains "bare repo's worktree is not INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"

NOTAREPO="$TEST_TMPDIR/res-notarepo"
mkdir -p "$NOTAREPO"
OUT=$(run "$TEST_TMPDIR/res-conv-wt" "$CFGRES" --project-root "$NOTAREPO" --worktree-root "$RESROOT")
assert_contains "non-checkout project-root reports the unread layer" "$OUT" "UNREAD LAYER"
assert_contains "non-checkout project-root summary is INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_not_contains "non-checkout project-root claims no shared main checkout" "$OUT" "plus the main checkout's shared settings.local.json"

git -C "$SUPER/sub" worktree add -q --detach "$TEST_TMPDIR/res-dead-wt"
DEADPATH="$(git -C "$SUPER/sub" rev-parse --show-toplevel | tr -d '\r')"
rm -rf "$SUPER/sub"
OUT=$(run "$TEST_TMPDIR/res-dead-wt" "$CFGRES" --worktree-root "$RESROOT")
assert_contains "a vanished main checkout is reported unread" "$OUT" "UNREAD LAYER"
assert_contains "a vanished main checkout makes the run INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_not_contains "a vanished main checkout is never named" "$OUT" "$DEADPATH"

CONV2="$TEST_TMPDIR/res-conv2"
git init -q "$CONV2"
commit_empty "$CONV2"
plant_main_deny "$CONV2"
git -C "$CONV2" worktree add -q --detach "$TEST_TMPDIR/res-conv2-wt"
mkdir -p "$TEST_TMPDIR/res-elsewhere"
git config -f "$CONV2/.git/config" core.worktree "$TEST_TMPDIR/res-elsewhere"
OUT=$(run "$TEST_TMPDIR/res-conv2-wt" "$CFGRES" --worktree-root "$RESROOT")
assert_contains "a parent that is not the tree is reported unread" "$OUT" "UNREAD LAYER"
assert_contains "a parent that is not the tree makes the run INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_not_contains "a parent that is not the tree is never named as the main checkout" "$OUT" \
  "includes the main checkout's settings.local.json ('"

PWREPO="$TEST_TMPDIR/layout-main"
git init -q "$PWREPO"
commit_empty "$PWREPO"
PWTOP="$(git -C "$PWREPO" rev-parse --show-toplevel)"
mkdir -p "$PWTOP/.claude"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$PWTOP/.claude/settings.local.json"
PWWT="$TEST_TMPDIR/layout-wt"
git -C "$PWREPO" worktree add -q --detach "$PWWT"
assert_eq "shared layout credits the main-local grant → no gap" "0" "$(run "$PWWT" "$CFG16" --count --worktree-root "$POSIX_CHILD")"
OTHER_UID=$(($(id -u) + 1))

WINUN="MINGW64_NT-10.0"
assert_eq "Windows layout: main-local-only grant is a gap" "1" "$(PREFLIGHT_UNAME="$WINUN" run "$PWWT" "$CFG16" --count --worktree-root "$POSIX_CHILD")"
OUT=$(PREFLIGHT_UNAME="$WINUN" run "$PWWT" "$CFG16" --worktree-root "$POSIX_CHILD")
assert_contains "Windows layout names the gap verb" "$OUT" "'gh pr create'"
assert_contains "Windows layout header names the cause" "$OUT" "per-worktree approvals layout (Windows)"
assert_not_contains "Windows layout is not INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_eq "MSYS and CYGWIN spellings are Windows too" "1 1" \
  "$(PREFLIGHT_UNAME=MSYS_NT run "$PWWT" "$CFG16" --count --worktree-root "$POSIX_CHILD") $(PREFLIGHT_UNAME=CYGWIN_NT run "$PWWT" "$CFG16" --count --worktree-root "$POSIX_CHILD")"
assert_eq "Windows layout from the main checkout does not credit its file to the fresh worker" "1" \
  "$(PREFLIGHT_UNAME="$WINUN" run "$PWREPO" "$CFG16" --count --worktree-root "$POSIX_CHILD")"
mkdir -p "$PWWT/.claude"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$PWWT/.claude/settings.local.json"
assert_eq "Windows layout, interactive: the worktree's own local grant counts" "0" "$(PREFLIGHT_UNAME="$WINUN" run "$PWWT" "$CFG16" --count)"
assert_eq "Windows layout, named worker: its own local grant counts" "0" \
  "$(PREFLIGHT_UNAME="$WINUN" run "$PWREPO" "$CFG16" --project-root "$PWWT" --count --worktree-root "$POSIX_CHILD")"
rm "$PWWT/.claude/settings.local.json"
jq -n '{permissions:{deny:["Bash(git commit *)"]}}' >"$PWTOP/.claude/settings.local.json"
OUT=$(PREFLIGHT_UNAME="$WINUN" run "$PWWT" "$CFG16D" --worktree-root "$POSIX_CHILD")
assert_contains "Windows layout still reads the main-local deny" "$OUT" "is DENIED"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$PWTOP/.claude/settings.local.json"

assert_eq "root not owned by the user: main-local-only grant is a gap" "1" "$(PREFLIGHT_UID="$OTHER_UID" run "$PWWT" "$CFG16" --count --worktree-root "$POSIX_CHILD")"
OUT=$(PREFLIGHT_UID="$OTHER_UID" run "$PWWT" "$CFG16" --worktree-root "$POSIX_CHILD")
assert_contains "ownership header names the cause" "$OUT" "root, .git or .claude not owned by the user"
mkdir -p "$PWWT/.claude"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$PWWT/.claude/settings.local.json"
assert_eq "root not owned by the user: the worktree's own local grant counts" "0" "$(PREFLIGHT_UID="$OTHER_UID" run "$PWWT" "$CFG16" --count)"
rm "$PWWT/.claude/settings.local.json"

assert_eq "root equal to HOME: main-local-only grant is a gap" "1" "$(run_home "$PWTOP" "$PWWT" "$CFG16" --count --worktree-root "$POSIX_CHILD")"
OUT=$(run_home "$PWTOP" "$PWWT" "$CFG16" --worktree-root "$POSIX_CHILD")
assert_contains "HOME header names the cause" "$OUT" "repository root is the home directory"
assert_eq "root under HOME is still shared" "0" "$(run_home "$TEST_TMPDIR" "$PWWT" "$CFG16" --count --worktree-root "$POSIX_CHILD")"
ln -s "$PWTOP" "$TEST_TMPDIR/layout-home-link"
assert_eq "root equal to a symlinked HOME: main-local-only grant is a gap" "1" "$(run_home "$TEST_TMPDIR/layout-home-link" "$PWWT" "$CFG16" --count --worktree-root "$POSIX_CHILD")"
OUT=$(run_home "$TEST_TMPDIR/layout-home-link" "$PWWT" "$CFG16" --worktree-root "$POSIX_CHILD")
assert_contains "symlinked HOME header names the cause" "$OUT" "repository root is the home directory"

for tag in ROOT GIT CLAUDE; do
  assert_eq "only $tag not owned by the user: main-local-only grant is a gap" "1" \
    "$(env "PREFLIGHT_OWNER_$tag=$OTHER_UID" PREFLIGHT_FIXTURE_DIR="$PWWT" CLAUDE_CONFIG_DIR="$CFG16" bash "$SCRIPT" --count --worktree-root "$POSIX_CHILD")"
done

OUT=$(PREFLIGHT_UID=unreadable run "$PWWT" "$CFG16" --worktree-root "$POSIX_CHILD")
assert_contains "undeterminable layout reports the unread layer" "$OUT" "UNREAD LAYER"
assert_contains "undeterminable layout does not credit the main-local grant" "$OUT" "'gh pr create'"
assert_contains "undeterminable layout ends INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_not_contains "undeterminable layout never claims OK" "$OUT" "PREFLIGHT: OK"
assert_eq "undeterminable layout leaves the gap uncredited" "1" "$(PREFLIGHT_UID=unreadable run "$PWWT" "$CFG16" --count --worktree-root "$POSIX_CHILD")"
assert_exit "undeterminable layout still exits 0 (report-only)" 0 "$(
  PREFLIGHT_UID=unreadable run "$PWWT" "$CFG16" --worktree-root "$POSIX_CHILD" >/dev/null
  echo $?
)"
OUT=$(PREFLIGHT_OWNER_GIT=unreadable run "$PWWT" "$CFG16" --worktree-root "$POSIX_CHILD")
assert_contains "unreadable owner reports the unread layer" "$OUT" "UNREAD LAYER"
assert_contains "unreadable owner ends INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
OUT=$(env -u HOME -u USERPROFILE PREFLIGHT_FIXTURE_DIR="$PWWT" CLAUDE_CONFIG_DIR="$CFG16" bash "$SCRIPT" --worktree-root "$POSIX_CHILD")
assert_contains "HOME and USERPROFILE unset reports the unread layer" "$OUT" "UNREAD LAYER"
assert_contains "HOME and USERPROFILE unset ends INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
OUT=$(PREFLIGHT_UNAME="" run "$PWWT" "$CFG16" --worktree-root "$POSIX_CHILD")
assert_contains "unreadable platform reports the unread layer" "$OUT" "UNREAD LAYER"
assert_contains "unreadable platform ends INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
OUT=$(PREFLIGHT_UID=unreadable run "$PWREPO" "$CFG16")
assert_not_contains "undeterminable layout from the main checkout is not INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_eq "undeterminable layout from the main checkout credits its own file" "0" "$(PREFLIGHT_UID=unreadable run "$PWREPO" "$CFG16" --count)"
OUT=$(PREFLIGHT_UID=unreadable run "$TEST_TMPDIR/res-bare-wt" "$CFGRES" --worktree-root "$RESROOT")
assert_not_contains "bare repo is not judged for layout" "$OUT" "approvals layout"

WORKER2="$TEST_TMPDIR/worker-local"
git init -q "$WORKER2"
WORKER2TOP="$(git -C "$WORKER2" rev-parse --show-toplevel)"
mkdir -p "$WORKER2TOP/.claude"
CFG17="$TEST_TMPDIR/cfg17"
write_settings "$CFG17" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$WORKER2TOP/.claude/settings.local.json"
assert_eq "distinct project-root reads the worker's own local grant" "0" "$(run "$REPO" "$CFG17" --project-root "$WORKER2" --count --worktree-root "$POSIX_CHILD")"
OUT=$(run "$REPO" "$CFG17" --project-root "$WORKER2" --worktree-root "$POSIX_CHILD")
assert_contains "distinct project-root header names the source" "$OUT" "from --project-root"
assert_eq "no distinct project-root excludes local → one gap" "1" "$(run "$REPO" "$CFG17" --count --worktree-root "$POSIX_CHILD")"

CFG18="$TEST_TMPDIR/cfg18"
# MSYS_NO_PATHCONV stops git-bash rewriting the bare "/" argument to the Git
# install root before jq sees it.
MSYS_NO_PATHCONV=1 write_settings "$CFG18" "$FULL_ALLOW" "/"
assert_eq "root additionalDirectories entry covers any worktree root" "0" "$(run "$REPO" "$CFG18" --count --worktree-root "$POSIX_CHILD")"

HOME19="$TEST_TMPDIR/home19"
mkdir -p "$HOME19"
CFG19="$TEST_TMPDIR/cfg19"
# shellcheck disable=SC2088  # the literal ~ entry is the input under test, not a path to expand
write_settings "$CFG19" "$FULL_ALLOW" "~/.worktrees"
OUT=$(run_home "$HOME19" "$REPO" "$CFG19" --worktree-root "$HOME19/.worktrees/999-x")
assert_not_contains "tilde-form entry covers an absolute child → no (c) gap" "$OUT" "GAP (c)"
assert_eq "tilde-form entry expands → zero gaps" "0" "$(run_home "$HOME19" "$REPO" "$CFG19" --count --worktree-root "$HOME19/.worktrees/999-x")"
assert_eq "tilde-form entry does not cover a root outside the home" "1" "$(run_home "$HOME19" "$REPO" "$CFG19" --count --worktree-root "$POSIX_CHILD")"

CFG19B="$TEST_TMPDIR/cfg19b"
# shellcheck disable=SC2088  # the literal ~ entry is the input under test, not a path to expand
write_settings "$CFG19B" "$FULL_ALLOW" "~${BS}.worktrees"
assert_eq "backslash-form tilde entry expands → zero gaps" "0" "$(run_home "$HOME19" "$REPO" "$CFG19B" --count --worktree-root "$HOME19/.worktrees/999-x")"

assert_eq "trailing-slash home still covers the child → zero gaps" "0" "$(run_home "$HOME19/" "$REPO" "$CFG19" --count --worktree-root "$HOME19/.worktrees/999-x")"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
