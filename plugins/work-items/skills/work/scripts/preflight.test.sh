#!/usr/bin/env bash
# Regression tests for preflight.sh (self-contained — ships with the plugin).
#
# Every check is injected via fixtures: PREFLIGHT_FIXTURE_DIR is the probe root
# (a bare temp dir is not-a-repo; `git init` makes it one) and CLAUDE_CONFIG_DIR
# points user-global settings at a fixture so the real ~/.claude never leaks in.
# Windows-path fixtures are assembled from separator fragments so no contiguous
# machine-path literal appears in this file's source bytes.
set -uo pipefail

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

# run <fixture-dir> <config-dir> [args...]
run() {
  local fx="$1" cfg="$2"
  shift 2
  PREFLIGHT_FIXTURE_DIR="$fx" CLAUDE_CONFIG_DIR="$cfg" bash "$SCRIPT" "$@"
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

FULL_ALLOW='["Bash(git add *)","Bash(git commit *)","Bash(git push)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"]'

# Runtime-assembled Windows path (no contiguous path literal in source).
# shellcheck disable=SC1003  # BS is a literal single backslash, not a quote escape
BS='\'
SL='/'
WIN_ROOT="D:${BS}repos${BS}.worktrees"
POSIX_CHILD="${SL}d${SL}repos${SL}.worktrees${SL}495-x"

# --- Case 1: --help ----------------------------------------------------------
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: missing jq exits 2 ---------------------------------------------
real_bash=$(command -v bash)
empty_path_dir="$TEST_TMPDIR/empty-path"
mkdir -p "$empty_path_dir"
rc=0
err_out=$(PATH="$empty_path_dir" "$real_bash" "$SCRIPT" 2>&1) || rc=$?
assert_exit "exit 2 when jq missing" 2 "$rc"
assert_contains "jq required message" "$err_out" "jq required"

# --- Case 3: clean repo, full grants, covered worktree root → OK -------------
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

# --- Case 4: non-repo cwd → NOTE (a), still zero gaps ------------------------
NONREPO="$TEST_TMPDIR/not-a-repo"
mkdir -p "$NONREPO"
OUT=$(run "$NONREPO" "$CFG3" --worktree-root "$POSIX_CHILD")
assert_contains "non-repo emits NOTE (a)" "$OUT" "NOTE (a)"
assert_contains "non-repo names the dir" "$OUT" "is not a git repository"
assert_eq "non-repo is a note, not a gap" "0" "$(run "$NONREPO" "$CFG3" --count --worktree-root "$POSIX_CHILD")"

# --- Case 5: missing verb → GAP (b) -----------------------------------------
CFG5="$TEST_TMPDIR/cfg5"
# All probe verbs but gh pr create (mirrors this fleet's interim-stopgap gap).
write_settings "$CFG5" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
OUT=$(run "$REPO" "$CFG5" --worktree-root "$POSIX_CHILD")
assert_contains "missing verb emits GAP (b)" "$OUT" "GAP (b)"
assert_contains "GAP names the missing verb" "$OUT" "'gh pr create'"
assert_contains "GAP points at the standards floor" "$OUT" "components/claude-permissions"
assert_not_contains "present verbs not flagged" "$OUT" "'git commit'"
assert_eq "one missing verb → one gap" "1" "$(run "$REPO" "$CFG5" --count --worktree-root "$POSIX_CHILD")"

# --- Case 5b: git add is a probed verb --------------------------------------
# A commit flow stages first, so `git add` must be probed alongside the others.
CFG5B="$TEST_TMPDIR/cfg5b"
# Everything but git add.
write_settings "$CFG5B" \
  '["Bash(git commit *)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
OUT=$(run "$REPO" "$CFG5B" --worktree-root "$POSIX_CHILD")
assert_contains "missing git add emits a gap" "$OUT" "'git add'"
assert_eq "git add is the only missing verb → one gap" "1" "$(run "$REPO" "$CFG5B" --count --worktree-root "$POSIX_CHILD")"

# --- Case 6: verb spelling variants all recognized --------------------------
CFG6="$TEST_TMPDIR/cfg6"
# Space open-glob (git commit *), colon open-glob (gh issue comment:*), and a
# PowerShell-spelled open glob (gh pr create *) — every probe covered by a
# distinct open-glob form (a bare-exact rule is NOT coverage; see case 7c).
write_settings "$CFG6" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","PowerShell(gh pr create *)","Bash(gh issue comment:*)"]'
# No worktree-root arg → (c) is a note, so --count reflects only the (b) verb probe.
assert_eq "all spelling variants recognized → 0 (b) gaps" "0" "$(run "$REPO" "$CFG6" --count)"
OUT=$(run "$REPO" "$CFG6")
assert_not_contains "spelling variants leave no (b) gap" "$OUT" "GAP (b)"

# --- Case 7: verb-boundary false-positive guard -----------------------------
CFG7="$TEST_TMPDIR/cfg7"
# git commit-tree must NOT satisfy the 'git commit' probe.
write_settings "$CFG7" \
  '["Bash(git add *)","Bash(git commit-tree *)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"]'
OUT=$(run "$REPO" "$CFG7" --worktree-root "$POSIX_CHILD")
assert_contains "commit-tree does not cover commit" "$OUT" "'git commit'"

# --- Case 7b: flag-specific rule does NOT cover the bare verb ----------------
CFG7B="$TEST_TMPDIR/cfg7b"
# A flag-scoped commit rule and a force-with-lease-only push rule are narrower
# than the plain verb — the lane's arbitrary `git commit` / `git push` would
# still prompt — so they must NOT count as coverage; only an open-glob form does.
write_settings "$CFG7B" \
  '["Bash(git add *)","Bash(git commit --amend)","Bash(git push --force-with-lease *)","Bash(gh pr create *)","Bash(gh issue comment *)"]'
OUT=$(run "$REPO" "$CFG7B")
assert_contains "flag-specific commit rule leaves git commit a gap" "$OUT" "'git commit'"
assert_contains "flag-specific push rule leaves git push a gap" "$OUT" "'git push'"
assert_not_contains "the open gh pr create rule is not a gap" "$OUT" "'gh pr create'"
assert_eq "two flag-masked verbs → two (b) gaps" "2" "$(run "$REPO" "$CFG7B" --count)"

# --- Case 7c: a bare-exact allow is not coverage, with a nuanced gap message -
CFG7C="$TEST_TMPDIR/cfg7c"
# Bash(git push) permits only the argumentless command (which babysit's fix cycle
# does run) but not the work lane's argument-carrying call, so it is still a GAP —
# reported with that nuance, not the generic missing-allow message.
write_settings "$CFG7C" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push)","Bash(gh pr create *)","Bash(gh issue comment *)"]'
OUT=$(run "$REPO" "$CFG7C")
assert_contains "bare-only push is still a gap" "$OUT" "'git push'"
assert_contains "gap names the bare-exact-only case" "$OUT" "bare-exact allow rule"
assert_contains "gap points at the open-glob remedy" "$OUT" "Grant the open glob"
assert_not_contains "bare-only push not the generic missing-allow message" "$OUT" "no Bash()/PowerShell() allow rule covers 'git push'"
assert_eq "bare-only allow → one gap" "1" "$(run "$REPO" "$CFG7C" --count)"

# --- Case 8: worktree root not covered → GAP (c) ----------------------------
CFG8="$TEST_TMPDIR/cfg8"
write_settings "$CFG8" "$FULL_ALLOW" "/some/other/root"
OUT=$(run "$REPO" "$CFG8" --worktree-root "$POSIX_CHILD")
assert_contains "uncovered root emits GAP (c)" "$OUT" "GAP (c)"
assert_contains "GAP (c) names additionalDirectories" "$OUT" "additionalDirectories"
assert_eq "uncovered root → one gap" "1" "$(run "$REPO" "$CFG8" --count --worktree-root "$POSIX_CHILD")"

# --- Case 9: cross-form Windows/POSIX path coverage --------------------------
# additionalDirectories entry in Windows form (D:\repos\.worktrees) must cover a
# child expressed in git-bash POSIX form (/d/repos/.worktrees/495-x).
assert_eq "Windows-form entry covers POSIX-form child" "0" "$(run "$REPO" "$CFG3" --count --worktree-root "$POSIX_CHILD")"

# --- Case 10: worktree root not provided → NOTE (c), no gap -----------------
OUT=$(run "$REPO" "$CFG3")
assert_contains "no root arg emits NOTE (c)" "$OUT" "NOTE (c)"
assert_contains "NOTE (c) explains it was not checked" "$OUT" "not checked"
assert_eq "no root arg is a note, not a gap" "0" "$(run "$REPO" "$CFG3" --count)"

# --- Case 11: interactive path unions in project settings.local.json --------
REPO2="$TEST_TMPDIR/proj-local"
mkdir -p "$REPO2"
git init -q "$REPO2"
PROJ="$(git -C "$REPO2" rev-parse --show-toplevel)"
mkdir -p "$PROJ/.claude"
# User-global misses gh pr create; project settings.local.json supplies it. The
# interactive/default path (no --worktree-root) reads local, so the gap closes.
# (The autonomous path excludes local — that is case 16.)
CFG11="$TEST_TMPDIR/cfg11"
write_settings "$CFG11" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$PROJ/.claude/settings.local.json"
assert_eq "interactive path reads settings.local.json" "0" "$(run "$REPO2" "$CFG11" --count)"

# --- Case 12: --count is a bare integer -------------------------------------
CNT=$(run "$NONREPO" "$CFG8" --count --worktree-root "$POSIX_CHILD")
assert_eq "count of the one (c) gap (note (a) excluded)" "1" "$CNT"

# --- Case 13: --project-root reads the worker worktree's own settings --------
# The main checkout grants gh pr create in its TRACKED project settings.json (a
# fresh worktree would carry it too); a dispatched worker worktree here does not.
# Without --project-root the main grant MASKS the worker gap; --project-root
# pointing at the worker surfaces it. Tracked (not local) so it is independent of
# the autonomous local-exclusion under test in case 16.
MAINCO="$TEST_TMPDIR/main-checkout"
git init -q "$MAINCO"
MAINTOP="$(git -C "$MAINCO" rev-parse --show-toplevel)"
mkdir -p "$MAINTOP/.claude"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$MAINTOP/.claude/settings.json"
WORKER="$TEST_TMPDIR/worker-worktree"
git init -q "$WORKER"
# User-global carries the other three probe verbs plus the trusted root, but not
# gh pr create — so only the project layer decides that verb.
CFG13="$TEST_TMPDIR/cfg13"
write_settings "$CFG13" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
assert_eq "main-checkout grant masks the gap without --project-root" "0" "$(run "$MAINCO" "$CFG13" --count --worktree-root "$POSIX_CHILD")"
OUT=$(run "$MAINCO" "$CFG13" --project-root "$WORKER" --worktree-root "$POSIX_CHILD")
assert_contains "--project-root surfaces the worker-side gap" "$OUT" "'gh pr create'"
assert_eq "worker-side gap counted under --project-root" "1" "$(run "$MAINCO" "$CFG13" --project-root "$WORKER" --count --worktree-root "$POSIX_CHILD")"

# write_deny <config-dir> <allow-json-array> <deny-json-array>
write_deny() {
  local cfg="$1" allow="$2" deny="$3"
  mkdir -p "$cfg"
  jq -n --argjson a "$allow" --argjson d "$deny" \
    '{permissions:{allow:$a, deny:$d}}' >"$cfg/settings.json"
}

# --- Case 14: allow + deny same verb → GAP (denied, deny wins) ---------------
CFG14="$TEST_TMPDIR/cfg14"
# git commit is BOTH allowed and denied (open-shape) — deny wins, so it stays a gap.
write_deny "$CFG14" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"]' \
  '["Bash(git commit *)"]'
OUT=$(run "$REPO" "$CFG14")
assert_contains "allowed-but-denied verb is a gap" "$OUT" "'git commit'"
assert_contains "denied gap has the distinct DENIED message" "$OUT" "is DENIED"
assert_not_contains "denied verb not reported as a missing-allow gap" "$OUT" "no Bash()/PowerShell() allow rule covers 'git commit'"
assert_eq "allow+deny same verb → exactly one gap" "1" "$(run "$REPO" "$CFG14" --count)"

# --- Case 15: deny-only verb → GAP (denied) ---------------------------------
CFG15="$TEST_TMPDIR/cfg15"
# git add is denied and not allowed anywhere; the other four are allowed.
write_deny "$CFG15" \
  '["Bash(git commit *)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"]' \
  '["Bash(git add)"]'
OUT=$(run "$REPO" "$CFG15")
assert_contains "deny-only verb is a gap" "$OUT" "'git add'"
assert_contains "deny-only gap has the DENIED message" "$OUT" "is DENIED"
assert_eq "deny-only verb → exactly one gap" "1" "$(run "$REPO" "$CFG15" --count)"

# --- Case 16: --worktree-root excludes settings.local.json from coverage -----
# A grant present ONLY in this checkout's gitignored settings.local.json is not
# carried by a fresh worktree. The interactive path reads local (gap closed); the
# autonomous path (--worktree-root) drops local, so the worker-side gap surfaces.
REPO3="$TEST_TMPDIR/local-mask"
git init -q "$REPO3"
PROJ3="$(git -C "$REPO3" rev-parse --show-toplevel)"
mkdir -p "$PROJ3/.claude"
CFG16="$TEST_TMPDIR/cfg16"
# User-global carries four verbs plus the trusted root; local supplies gh pr create.
write_settings "$CFG16" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$PROJ3/.claude/settings.local.json"
assert_eq "interactive path reads local grant → no gap" "0" "$(run "$REPO3" "$CFG16" --count)"
OUT=$(run "$REPO3" "$CFG16" --worktree-root "$POSIX_CHILD")
assert_contains "autonomous path drops local → gh pr create gap surfaces" "$OUT" "'gh pr create'"
assert_contains "report header notes the local exclusion" "$OUT" "settings.local.json"
assert_eq "autonomous path drops local grant → one gap" "1" "$(run "$REPO3" "$CFG16" --count --worktree-root "$POSIX_CHILD")"

# --- Case 17: a distinct --project-root reads the worker's OWN local settings -
# When --project-root names a real worker worktree (toplevel differs from cwd),
# read ITS OWN settings.local.json — the worker's file, present in that checkout —
# instead of excluding local. The pre-dispatch exclusion (case 16) applies only
# when no distinct --project-root is given.
WORKER2="$TEST_TMPDIR/worker-local"
git init -q "$WORKER2"
WORKER2TOP="$(git -C "$WORKER2" rev-parse --show-toplevel)"
mkdir -p "$WORKER2TOP/.claude"
CFG17="$TEST_TMPDIR/cfg17"
# gh pr create lives ONLY in the worker's own local file; user-global lacks it.
write_settings "$CFG17" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$WORKER2TOP/.claude/settings.local.json"
assert_eq "distinct project-root reads the worker's own local grant" "0" "$(run "$REPO" "$CFG17" --project-root "$WORKER2" --count --worktree-root "$POSIX_CHILD")"
OUT=$(run "$REPO" "$CFG17" --project-root "$WORKER2" --worktree-root "$POSIX_CHILD")
assert_contains "distinct project-root header names the source" "$OUT" "from --project-root"
# Without the distinct --project-root (pre-dispatch), local is excluded → gap.
assert_eq "no distinct project-root excludes local → one gap" "1" "$(run "$REPO" "$CFG17" --count --worktree-root "$POSIX_CHILD")"

# --- Case 18: filesystem root entry authorizes every absolute path ------------
CFG18="$TEST_TMPDIR/cfg18"
# MSYS_NO_PATHCONV stops git-bash rewriting the bare "/" argument to the Git
# install root before jq sees it.
MSYS_NO_PATHCONV=1 write_settings "$CFG18" "$FULL_ALLOW" "/"
assert_eq "root additionalDirectories entry covers any worktree root" "0" "$(run "$REPO" "$CFG18" --count --worktree-root "$POSIX_CHILD")"

# --- Case 19: tilde-form additionalDirectories entry expands to the user home -
# A ~-form entry (~/.worktrees) must expand to $HOME and cover an absolute probed
# root beneath it — the grant the harness's own tilde expansion makes live but
# normalize_path previously left unmatched. HOME is set explicitly so the case is
# independent of the tester's real home.
HOME19="$TEST_TMPDIR/home19"
mkdir -p "$HOME19"
CFG19="$TEST_TMPDIR/cfg19"
# shellcheck disable=SC2088  # the literal ~ entry is the input under test, not a path to expand
write_settings "$CFG19" "$FULL_ALLOW" "~/.worktrees"
# run_home <home> <fixture-dir> <config-dir> [args...] — like run(), with HOME set
# so a tilde-form entry expands deterministically. CLAUDE_CONFIG_DIR still points
# settings at the fixture, so HOME only steers normalize_path's ~ expansion.
run_home() {
  local home="$1" fx="$2" cfg="$3"
  shift 3
  HOME="$home" PREFLIGHT_FIXTURE_DIR="$fx" CLAUDE_CONFIG_DIR="$cfg" bash "$SCRIPT" "$@"
}
OUT=$(run_home "$HOME19" "$REPO" "$CFG19" --worktree-root "$HOME19/.worktrees/999-x")
assert_not_contains "tilde-form entry covers an absolute child → no (c) gap" "$OUT" "GAP (c)"
assert_eq "tilde-form entry expands → zero gaps" "0" "$(run_home "$HOME19" "$REPO" "$CFG19" --count --worktree-root "$HOME19/.worktrees/999-x")"
# The expansion is a real ancestor check, not a blanket pass: a root outside the
# expanded home is still an uncovered (c) gap, and non-tilde probes are unchanged.
assert_eq "tilde-form entry does not cover a root outside the home" "1" "$(run_home "$HOME19" "$REPO" "$CFG19" --count --worktree-root "$POSIX_CHILD")"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
