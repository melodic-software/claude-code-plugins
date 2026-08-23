#!/usr/bin/env bash
# Regression tests for preflight.sh (self-contained — ships with the plugin).
#
# Every check is injected via fixtures: PREFLIGHT_FIXTURE_DIR is the probe root
# (a bare temp dir is not-a-repo; `git init` makes it one) and CLAUDE_CONFIG_DIR
# points user-global settings at a fixture so the real ~/.claude never leaks in.
# Windows-path fixtures are assembled from separator fragments so no contiguous
# machine-path literal appears in this file's source bytes.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

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

# --- Case 16: the main checkout's settings.local.json follows the worker -----
# Since Claude Code v2.1.211, "don't ask again" approvals save to the MAIN
# checkout's settings.local.json and apply in every worktree of the repository —
# so a grant there is real coverage for a fresh worker, and the autonomous path
# reads it instead of dropping it.
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
assert_contains "header states the main-local inclusion basis" "$OUT" \
  "includes this main checkout's settings.local.json: since Claude Code v2.1.211"
assert_eq "autonomous path reads the main checkout's local grant → no gap" "0" "$(run "$REPO3" "$CFG16" --count --worktree-root "$POSIX_CHILD")"

# --- Case 16b: a linked worktree's OWN local file is still excluded ----------
# A rule saved inside a worktree (pre-2.1.211 harness, or hand-placed) applies
# only to sessions started there, so a fresh worker would not inherit it. From a
# worktree cwd the autonomous path keeps the main checkout's local file but
# drops the worktree's own.
git -C "$REPO3" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
WT16="$TEST_TMPDIR/local-mask-wt"
git -C "$REPO3" worktree add -q --detach "$WT16"
# Main-local grant (case 16's file) reaches a worktree cwd's autonomous run.
assert_eq "main checkout's local grant covers from a worktree cwd → no gap" "0" "$(run "$WT16" "$CFG16" --count --worktree-root "$POSIX_CHILD")"
# Move the grant into the worktree's own local file only.
rm "$PROJ3/.claude/settings.local.json"
mkdir -p "$WT16/.claude"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$WT16/.claude/settings.local.json"
assert_eq "interactive path in the worktree reads its own local → no gap" "0" "$(run "$WT16" "$CFG16" --count)"
OUT=$(run "$WT16" "$CFG16" --worktree-root "$POSIX_CHILD")
assert_contains "autonomous path drops the worktree's own local → gap surfaces" "$OUT" "'gh pr create'"
assert_contains "header notes the worktree-local exclusion" "$OUT" "excludes this worktree's own local file"
assert_eq "worktree-local-only grant → one gap" "1" "$(run "$WT16" "$CFG16" --count --worktree-root "$POSIX_CHILD")"

# --- Case 16c: a main checkout whose git dir is not spelled "<root>/.git" -----
# --separate-git-dir (and a submodule checkout) put the common dir elsewhere. The
# checkout is still the MAIN one, so its local file still reaches a fresh worker
# and must not be dropped on the autonomous path.
SEPCO="$TEST_TMPDIR/sep-main"
git init -q --separate-git-dir "$TEST_TMPDIR/sep-gitdir" "$SEPCO"
SEPTOP="$(git -C "$SEPCO" rev-parse --show-toplevel)"
mkdir -p "$SEPTOP/.claude"
jq -n '{permissions:{allow:["Bash(gh pr create *)"]}}' >"$SEPTOP/.claude/settings.local.json"
assert_eq "separate-git-dir main checkout's local grant counts → no gap" "0" "$(run "$SEPCO" "$CFG16" --count --worktree-root "$POSIX_CHILD")"

# --- Case 16d: the main checkout's local DENY reaches a worktree run ---------
# Deny reads the main checkout's local file too. Every other deny case writes to
# user-global only, so without this, dropping main-local from the deny path would
# narrow deny silently and leave the suite green.
CFG16D="$TEST_TMPDIR/cfg16d"
write_settings "$CFG16D" \
  '["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"]' \
  "$WIN_ROOT"
jq -n '{permissions:{deny:["Bash(git push *)"]}}' >"$PROJ3/.claude/settings.local.json"
OUT=$(run "$WT16" "$CFG16D" --worktree-root "$POSIX_CHILD")
assert_contains "main-local deny reaches a worktree run" "$OUT" "'git push'"
assert_contains "main-local deny carries the DENIED message" "$OUT" "is DENIED"
assert_eq "main-local deny → exactly one gap" "1" "$(run "$WT16" "$CFG16D" --count --worktree-root "$POSIX_CHILD")"

# --- Main-checkout resolution across git-dir spellings (cases 16e–16j) --------
# The recovery used to be path arithmetic on the common dir, so any spelling but
# "<root>/.git" left the main checkout unresolved and its local file dropped from
# EVERY read, deny included — silently, under a "PREFLIGHT: OK". Each case below
# plants a real main-local DENY and asserts it is either reported (the layer was
# read) or that the run says loudly that the layer was NOT read. Deny is the
# probe because it is the masking direction: a dropped deny under-reports.
#
# commit_empty <repo> — a commit so `worktree add` has a HEAD to detach from.
commit_empty() {
  git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -F - --cleanup=verbatim <<'MSG'
init
MSG
}
# plant_main_deny <checkout> — the main checkout's local file carries a deny and
# nothing else, so any report of 'git push' proves that file was read.
plant_main_deny() {
  mkdir -p "$1/.claude"
  jq -n '{permissions:{deny:["Bash(git push *)"]}}' >"$1/.claude/settings.local.json"
}
# CFGRES allows all five verbs and trusts the filesystem root, so ONLY a deny can
# produce a gap — a nonzero count means the main-local layer reached the read.
CFGRES="$TEST_TMPDIR/cfg-res"
mkdir -p "$CFGRES"
MSYS_NO_PATHCONV=1 jq -n '{permissions:{allow:["Bash(git add *)","Bash(git commit *)","Bash(git push *)","Bash(gh pr create *)","Bash(gh issue comment *)"],additionalDirectories:["/"]}}' >"$CFGRES/settings.json"
RESROOT="$TEST_TMPDIR/res-wtroot"

# --- Case 16e: conventional linked worktree still resolves (no regression) ----
CONV="$TEST_TMPDIR/res-conv"
git init -q "$CONV"
commit_empty "$CONV"
plant_main_deny "$CONV"
git -C "$CONV" worktree add -q --detach "$TEST_TMPDIR/res-conv-wt"
OUT=$(run "$TEST_TMPDIR/res-conv-wt" "$CFGRES" --worktree-root "$RESROOT")
assert_contains "conventional worktree reports the main-local deny" "$OUT" "is DENIED"
assert_not_contains "conventional worktree is not INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_eq "conventional worktree → one gap" "1" "$(run "$TEST_TMPDIR/res-conv-wt" "$CFGRES" --count --worktree-root "$RESROOT")"

# --- Case 16f: a submodule's linked worktree resolves via core.worktree -------
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

# --- Case 16f2: core.worktree defined through [include] is honored ------------
# A config may hold core.worktree only via an include directive; `git config -f`
# never processes includes, so the resolution must read with GIT_DIR context.
SUBGITDIR="$(git -C "$SUPER/sub" rev-parse --git-common-dir | tr -d '\r')"
INCWT="$(git config -f "$SUBGITDIR/config" --get core.worktree | tr -d '\r')"
git config -f "$SUBGITDIR/config" --unset core.worktree
printf '[core]\n\tworktree = %s\n' "$INCWT" > "$SUBGITDIR/worktree.inc"
printf '[include]\n\tpath = worktree.inc\n' >> "$SUBGITDIR/config"
OUT=$(run "$TEST_TMPDIR/res-sub-wt" "$CFGRES" --worktree-root "$RESROOT")
assert_contains "include-defined core.worktree still reports the deny" "$OUT" "is DENIED"
assert_not_contains "include-defined core.worktree is not INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"

# --- Case 16g: an unresolvable spelling is LOUD, never "PREFLIGHT: OK" --------
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

# --- Case 16h: the INTERACTIVE path is loud too -------------------------------
# Both headers that name a main checkout print only under --worktree-root or a
# distinct --project-root, so a plain run from an unresolvable linked worktree
# used to drop a main-local deny with no output whatsoever.
OUT=$(run "$TEST_TMPDIR/res-sep2-wt" "$CFGRES")
assert_contains "interactive path reports the unread layer" "$OUT" "UNREAD LAYER"
assert_contains "interactive path summary is INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_not_contains "interactive path never claims OK" "$OUT" "PREFLIGHT: OK"

# --- Case 16i: a bare repository has no main checkout — not an unread layer ---
# Nothing is missing (a bare repo holds no working tree, so no main-local file can
# exist), so INCOMPLETE here would be the same false alarm this change removes.
git clone -q --bare "$CONV" "$TEST_TMPDIR/res-bare.git" 2>/dev/null
git -C "$TEST_TMPDIR/res-bare.git" worktree add -q --detach "$TEST_TMPDIR/res-bare-wt"
OUT=$(run "$TEST_TMPDIR/res-bare-wt" "$CFGRES" --worktree-root "$RESROOT")
assert_contains "bare repo's worktree reports OK" "$OUT" "PREFLIGHT: OK"
assert_not_contains "bare repo's worktree is not INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"

# --- Case 16j: --project-root naming a non-checkout is unresolved, not named --
# The old arithmetic would happily name a directory it never verified.
NOTAREPO="$TEST_TMPDIR/res-notarepo"
mkdir -p "$NOTAREPO"
OUT=$(run "$TEST_TMPDIR/res-conv-wt" "$CFGRES" --project-root "$NOTAREPO" --worktree-root "$RESROOT")
assert_contains "non-checkout project-root reports the unread layer" "$OUT" "UNREAD LAYER"
assert_contains "non-checkout project-root summary is INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_not_contains "non-checkout project-root claims no shared main checkout" "$OUT" "plus the main checkout's shared settings.local.json"

# --- Case 16k: a candidate that no longer exists is rejected, not named -------
# Removing a submodule's working tree leaves core.worktree pointing at a dead
# path. Without the verification predicate that path would be named as the main
# checkout and read straight through — a directory that is not there.
git -C "$SUPER/sub" worktree add -q --detach "$TEST_TMPDIR/res-dead-wt"
DEADPATH="$(git -C "$SUPER/sub" rev-parse --show-toplevel | tr -d '\r')"
rm -rf "$SUPER/sub"
OUT=$(run "$TEST_TMPDIR/res-dead-wt" "$CFGRES" --worktree-root "$RESROOT")
assert_contains "a vanished main checkout is reported unread" "$OUT" "UNREAD LAYER"
assert_contains "a vanished main checkout makes the run INCOMPLETE" "$OUT" "PREFLIGHT: INCOMPLETE"
assert_not_contains "a vanished main checkout is never named" "$OUT" "$DEADPATH"

# --- Case 16l: the conventional parent is rejected when it is not the tree ----
# "<X>/.git is the common dir" does not by itself make <X> the working tree. Here
# the common dir's core.worktree names somewhere else, so <X>'s own toplevel
# disagrees and the candidate must be discarded — the old arithmetic returned <X>
# unconditionally, which is what let a non-checkout be named as the main one.
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

# --- Case 19b: backslash-form tilde entry (~\...) also expands ----------------
# A Windows entry may be written ~\.worktrees; that separator must expand the
# same as ~/.worktrees (the repo's other portable expanders accept both forms).
CFG19B="$TEST_TMPDIR/cfg19b"
# shellcheck disable=SC2088  # the literal ~ entry is the input under test, not a path to expand
write_settings "$CFG19B" "$FULL_ALLOW" "~${BS}.worktrees"
assert_eq "backslash-form tilde entry expands → zero gaps" "0" "$(run_home "$HOME19" "$REPO" "$CFG19B" --count --worktree-root "$HOME19/.worktrees/999-x")"

# --- Case 19c: a trailing separator on the home does not double on the join --
# HOME ending in / (or \) must not yield //.worktrees, which normalize_path does
# not collapse and so would not match the absolute probed root.
assert_eq "trailing-slash home still covers the child → zero gaps" "0" "$(run_home "$HOME19/" "$REPO" "$CFG19" --count --worktree-root "$HOME19/.worktrees/999-x")"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
