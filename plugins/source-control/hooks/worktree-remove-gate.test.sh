#!/usr/bin/env bash
# Regression tests for worktree-remove-gate.sh (WorktreeRemove hook).
# Black-box: feed the hook a WorktreeRemove payload against throwaway git
# fixtures, with a stubbed `claude` on PATH that keeps install records in a JSON
# file, so the reap runs through reap-project-plugin-records.sh unchanged.
# No network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/worktree-remove-gate.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=../scripts/test-helpers.sh
source "$SCRIPT_DIR/../scripts/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"
command -v jq >/dev/null 2>&1 || skip_suite "jq not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

STUB_DIR="$TEST_TMPDIR/stub"
mkdir -p "$STUB_DIR"
STATE="$TEST_TMPDIR/state.json"
LOG="$TEST_TMPDIR/calls.log"

# The measured CLI contract, as in reap-project-plugin-records.test.sh: `plugin
# list --json` reports every record whatever the cwd; `plugin uninstall` removes
# only a record whose projectPath is the cwd. STUB_UNINSTALL_FAIL=1 makes every
# uninstall fail, so the record survives the reap. STUB_REWRITE_SETTINGS=1 makes
# a project-scope uninstall rewrite the cwd's .claude/settings.json.
cat >"$STUB_DIR/claude" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >>"$STUB_CALL_LOG"

stub_native_pwd() {
  local p
  p="$(pwd -W 2>/dev/null)" || p=""
  [[ -n "$p" ]] || p="$(pwd -P 2>/dev/null)" || p="$PWD"
  printf '%s' "$p"
}
stub_key() {
  local p="${1//\\//}"
  while [[ "$p" == */ && ${#p} -gt 1 ]]; do p="${p%/}"; done
  printf '%s' "$p" | tr '[:upper:]' '[:lower:]'
}

if [[ "${1:-}" == "plugin" && "${2:-}" == "list" ]]; then
  [[ "${STUB_LIST_FAIL:-0}" == 1 ]] && exit 1
  jq -c '{installed: .}' "$STUB_STATE"
  exit 0
fi

if [[ "${1:-}" == "plugin" && "${2:-}" == "uninstall" ]]; then
  id="${3:-}"
  scope=""
  shift 3
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -s | --scope)
      scope="${2:-}"
      shift 2
      ;;
    *) shift ;;
    esac
  done
  [[ "${STUB_UNINSTALL_FAIL:-0}" == 1 ]] && exit 1
  here="$(stub_key "$(stub_native_pwd)")"
  sel='.id == $id and .scope == $scope
    and ((.projectPath // "") | gsub("\\\\"; "/") | ascii_downcase | sub("/$"; "")) == $here'
  hit="$(jq -r --arg id "$id" --arg here "$here" --arg scope "$scope" "map(select($sel)) | length" "$STUB_STATE")"
  if [[ "$hit" -gt 0 ]]; then
    tmp="$(mktemp)"
    jq --arg id "$id" --arg here "$here" --arg scope "$scope" "map(select(($sel) | not))" \
      "$STUB_STATE" >"$tmp" && mv "$tmp" "$STUB_STATE"
    # The reported side effect: a project-scope uninstall also rewrites the
    # cwd's .claude/settings.json, dropping entries and unrelated settings.
    if [[ "${STUB_REWRITE_SETTINGS:-0}" == 1 && "$scope" == "project" ]]; then
      mkdir -p .claude
      printf '{\n  "enabledPlugins": {}\n}\n' >.claude/settings.json
      printf 'rewrote .claude/settings.json\n' >>"$STUB_CALL_LOG"
    fi
    printf 'Successfully uninstalled plugin: %s (scope: %s)\n' "$id" "$scope"
    exit 0
  fi
  printf 'Failed to uninstall plugin "%s": Plugin "%s" is installed in user scope, not project. Use --scope user to uninstall.\n' "$id" "$id" >&2
  exit 1
fi

printf 'stub: unhandled: %s\n' "$*" >&2
exit 64
STUB
chmod +x "$STUB_DIR/claude"

native_of() { (cd "$1" && { pwd -W 2>/dev/null || pwd -P; }); }

mkrepo() {
  local repo
  repo="$(mktemp -d "$TEST_TMPDIR/repoXXXXXX")"
  {
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email t@t.t
    git -C "$repo" config user.name t
    git -C "$repo" config commit.gpgsign false
    printf 'seed\n' >"$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit -qm init
  } >/dev/null 2>&1
  printf '%s' "$repo"
}

REPO="$(mkrepo)"
OTHER="$TEST_TMPDIR/other"
mkdir -p "$OTHER"
OTHER_NATIVE="$(native_of "$OTHER")"

# mkwt <name> — a linked worktree of REPO on a new branch <name>, outside the
# repository; prints its native path.
mkwt() {
  git -C "$REPO" worktree add -q -b "$1" "$TEST_TMPDIR/wt-$1" >/dev/null 2>&1
  native_of "$TEST_TMPDIR/wt-$1"
}

# seed <path> — a project and a local record for <path>, and one for OTHER.
seed() {
  jq -n --arg p "$1" --arg o "$OTHER_NATIVE" '[
    {id: "alpha@m", scope: "project", projectPath: $p},
    {id: "beta@m", scope: "local", projectPath: $p},
    {id: "alpha@m", scope: "project", projectPath: $o}
  ]' >"$STATE"
}

records_for() { jq --arg p "$1" '[.[] | select(.projectPath == $p)] | length' "$STATE"; }

payload() {
  jq -cn --arg p "$1" --arg s "${2:-s1}" \
    '{session_id: $s, transcript_path: "t", cwd: "/", hook_event_name: "WorktreeRemove", worktree_path: $p}'
}

# run_hook <payload> [VAR=value ...] — one hook run with the stub on PATH.
RC=0
OUT=""
ERR=""
run_hook() {
  local json="$1"
  shift
  : >"$LOG"
  OUT="$(printf '%s' "$json" |
    env PATH="$STUB_DIR:$PATH" STUB_STATE="$STATE" STUB_CALL_LOG="$LOG" "$@" \
      bash "$HOOK" 2>"$TEST_TMPDIR/err")"
  RC=$?
  ERR="$(cat "$TEST_TMPDIR/err")"
}

on_disk() { if [[ -e "$1" ]]; then printf 'present'; else printf 'absent'; fi; }

# --------------------------------------------------------------------------
# A clean worktree: records reaped, directory and git entry removed
# --------------------------------------------------------------------------

WT="$(mkwt clean)"
seed "$WT"
run_hook "$(payload "$WT")"
assert_exit "a clean worktree is removed" 0 "$RC"
assert_silent "the hook prints nothing on stdout" "$OUT"
assert_eq "the directory is gone" "absent" "$(on_disk "$WT")"
assert_not_contains "git no longer lists the worktree" "$(git -C "$REPO" worktree list)" "wt-clean"
assert_eq "its records are reaped" "0" "$(records_for "$WT")"
assert_eq "another path's record is untouched" "1" "$(records_for "$OTHER_NATIVE")"
assert_contains "the reap ran the project-scope uninstall" "$(cat "$LOG")" "plugin uninstall alpha@m -s project --keep-data"
assert_contains "the reap ran the local-scope uninstall" "$(cat "$LOG")" "plugin uninstall beta@m -s local --keep-data"
git -C "$REPO" rev-parse --verify -q refs/heads/clean >/dev/null 2>&1
assert_exit "the branch is kept" 0 "$?"

# --------------------------------------------------------------------------
# The uninstall rewrites the tracked .claude/settings.json: the reap restores
# it from git, so the plain removal after it still succeeds
# --------------------------------------------------------------------------

WT_SETTINGS="$(mkwt settings)"
{
  mkdir -p "$WT_SETTINGS/.claude"
  printf '{\n  "enabledPlugins": {"alpha@m": true},\n  "model": "keep"\n}\n' >"$WT_SETTINGS/.claude/settings.json"
  git -C "$WT_SETTINGS" add .claude/settings.json
  git -C "$WT_SETTINGS" commit -qm settings
} >/dev/null 2>&1
seed "$WT_SETTINGS"
run_hook "$(payload "$WT_SETTINGS")" STUB_REWRITE_SETTINGS=1
assert_contains "the uninstall rewrote the tracked settings file" "$(cat "$LOG")" "rewrote .claude/settings.json"
assert_exit "a worktree whose tracked settings the uninstall rewrote is removed" 0 "$RC"
assert_eq "the rewritten worktree is gone" "absent" "$(on_disk "$WT_SETTINGS")"
assert_not_contains "git no longer lists the rewritten worktree" "$(git -C "$REPO" worktree list)" "wt-settings"
assert_eq "the rewritten worktree's records are reaped" "0" "$(records_for "$WT_SETTINGS")"

# --------------------------------------------------------------------------
# Uncommitted or untracked work: left on disk, nothing reaped, non-zero exit
# --------------------------------------------------------------------------

WT_DIRTY="$(mkwt dirty)"
printf 'edit\n' >>"$WT_DIRTY/README.md"
seed "$WT_DIRTY"
run_hook "$(payload "$WT_DIRTY")"
assert_exit "an uncommitted change refuses" 1 "$RC"
assert_eq "the dirty worktree stays on disk" "present" "$(on_disk "$WT_DIRTY/README.md")"
assert_contains "git still lists the dirty worktree" "$(git -C "$REPO" worktree list)" "wt-dirty"
assert_eq "nothing is reaped for the dirty worktree" "2" "$(records_for "$WT_DIRTY")"
assert_silent "no uninstall ran for the dirty worktree" "$(cat "$LOG")"
assert_contains "the refusal names the uncommitted work" "$ERR" "uncommitted or untracked"
assert_eq "the remedy leads" "1" "$(printf '%s\n' "$ERR" | grep -n 'commit, stash or discard' | cut -d: -f1)"

WT_UNTRACKED="$(mkwt untracked)"
printf 'notes\n' >"$WT_UNTRACKED/notes.txt"
seed "$WT_UNTRACKED"
run_hook "$(payload "$WT_UNTRACKED")"
assert_exit "an untracked file refuses" 1 "$RC"
assert_eq "the untracked file stays on disk" "present" "$(on_disk "$WT_UNTRACKED/notes.txt")"
assert_eq "nothing is reaped for the untracked worktree" "2" "$(records_for "$WT_UNTRACKED")"

# --------------------------------------------------------------------------
# A reap failure: directory and git entry left, non-zero exit
# --------------------------------------------------------------------------

WT_NOLIST="$(mkwt nolist)"
seed "$WT_NOLIST"
run_hook "$(payload "$WT_NOLIST")" STUB_LIST_FAIL=1
assert_exit "a reap that cannot enumerate refuses" 1 "$RC"
assert_eq "the worktree stays when the reap degrades" "present" "$(on_disk "$WT_NOLIST")"
assert_contains "git still lists it" "$(git -C "$REPO" worktree list)" "wt-nolist"
assert_contains "the refusal names the reap exit" "$ERR" "the reap exited 3"

WT_SURVIVOR="$(mkwt survivor)"
seed "$WT_SURVIVOR"
run_hook "$(payload "$WT_SURVIVOR")" STUB_UNINSTALL_FAIL=1
assert_exit "a record that survives the reap refuses" 1 "$RC"
assert_eq "the worktree stays when a record survives" "present" "$(on_disk "$WT_SURVIVOR")"
assert_eq "the surviving records are still recorded" "2" "$(records_for "$WT_SURVIVOR")"
assert_contains "the refusal names the reap exit" "$ERR" "the reap exited 1"

# --------------------------------------------------------------------------
# Locks: this session's lock is released; another's is refused
# --------------------------------------------------------------------------

WT_OURS="$(mkwt ours)"
git -C "$REPO" worktree lock --reason "worktree-create.sh: lane active on h session s1 since 2026-10-26T00:00:00Z" "$WT_OURS"
seed "$WT_OURS"
run_hook "$(payload "$WT_OURS/" s1)"
assert_exit "a worktree locked by this session is removed (trailing slash in the path)" 0 "$RC"
assert_eq "the locked worktree is gone" "absent" "$(on_disk "$WT_OURS")"
assert_eq "its records are reaped" "0" "$(records_for "$WT_OURS")"

WT_FOREIGN="$(mkwt foreign)"
git -C "$REPO" worktree lock --reason "worktree-create.sh: lane active on h session s10 since 2026-10-26T00:00:00Z" "$WT_FOREIGN"
seed "$WT_FOREIGN"
run_hook "$(payload "$WT_FOREIGN" s1)"
assert_exit "a lock naming another session refuses" 1 "$RC"
assert_eq "the foreign-locked worktree stays" "present" "$(on_disk "$WT_FOREIGN")"
assert_eq "nothing is reaped under a foreign lock" "2" "$(records_for "$WT_FOREIGN")"
assert_contains "the lock stays armed" "$(git -C "$REPO" worktree list --porcelain)" "session s10 since"

# --------------------------------------------------------------------------
# A detached HEAD holding commits nothing else holds
# --------------------------------------------------------------------------

WT_DETACHED="$(mkwt detached)"
{
  git -C "$WT_DETACHED" checkout -q --detach
  printf 'more\n' >>"$WT_DETACHED/README.md"
  git -C "$WT_DETACHED" commit -qam detached-only
} >/dev/null 2>&1
seed "$WT_DETACHED"
run_hook "$(payload "$WT_DETACHED")"
assert_exit "a detached HEAD with unheld commits refuses" 1 "$RC"
assert_eq "the detached worktree stays" "present" "$(on_disk "$WT_DETACHED")"
assert_eq "nothing is reaped for the detached worktree" "2" "$(records_for "$WT_DETACHED")"

WT_HELD="$(mkwt held)"
git -C "$WT_HELD" checkout -q --detach >/dev/null 2>&1
seed "$WT_HELD"
run_hook "$(payload "$WT_HELD")"
assert_exit "a detached HEAD whose commits a branch holds is removed" 0 "$RC"
assert_eq "the held detached worktree is gone" "absent" "$(on_disk "$WT_HELD")"

# --------------------------------------------------------------------------
# State git status cannot see: an operation in progress, submodules
# --------------------------------------------------------------------------

WT_REBASE="$(mkwt rebase)"
mkdir -p "$(git -C "$WT_REBASE" rev-parse --absolute-git-dir)/rebase-merge"
seed "$WT_REBASE"
run_hook "$(payload "$WT_REBASE")"
assert_exit "a rebase in progress refuses, though git status is clean" 1 "$RC"
assert_eq "the worktree mid-rebase stays" "present" "$(on_disk "$WT_REBASE")"
assert_eq "nothing is reaped mid-rebase" "2" "$(records_for "$WT_REBASE")"
assert_contains "the refusal names the operation" "$ERR" "rebase-merge"

WT_SUB="$(mkwt sub)"
{
  printf '[submodule "lib"]\n\tpath = lib\n\turl = ../lib\n' >"$WT_SUB/.gitmodules"
  git -C "$WT_SUB" add .gitmodules
  git -C "$WT_SUB" commit -qm submodules
} >/dev/null 2>&1
seed "$WT_SUB"
run_hook "$(payload "$WT_SUB")"
assert_exit "a worktree with submodules refuses before the reap" 1 "$RC"
assert_eq "the worktree with submodules stays" "present" "$(on_disk "$WT_SUB")"
assert_eq "nothing is reaped for the worktree with submodules" "2" "$(records_for "$WT_SUB")"

WT_NOREASON="$(mkwt noreason)"
git -C "$REPO" worktree lock "$WT_NOREASON"
seed "$WT_NOREASON"
run_hook "$(payload "$WT_NOREASON" s1)"
assert_exit "a lock with no reason refuses" 1 "$RC"
assert_eq "the reasonless-locked worktree stays" "present" "$(on_disk "$WT_NOREASON")"
assert_eq "nothing is reaped under a reasonless lock" "2" "$(records_for "$WT_NOREASON")"

# --------------------------------------------------------------------------
# Paths the hook never acts on
# --------------------------------------------------------------------------

REPO_NATIVE="$(native_of "$REPO")"
seed "$REPO_NATIVE"
run_hook "$(payload "$REPO_NATIVE")"
assert_exit "a main working tree refuses" 1 "$RC"
assert_eq "the main working tree stays" "present" "$(on_disk "$REPO/README.md")"
assert_eq "nothing is reaped for the main working tree" "2" "$(records_for "$REPO_NATIVE")"

PLAIN="$TEST_TMPDIR/plain"
mkdir -p "$PLAIN"
printf 'keep\n' >"$PLAIN/work.txt"
run_hook "$(payload "$(native_of "$PLAIN")")"
assert_exit "a directory that is not a git worktree refuses" 1 "$RC"
assert_eq "its contents stay" "present" "$(on_disk "$PLAIN/work.txt")"

run_hook "$(payload "$TEST_TMPDIR/never-existed")"
assert_exit "a path already gone exits 0" 0 "$RC"

run_hook "$(payload "relative/path")"
assert_exit "a relative path refuses" 1 "$RC"

run_hook '{"session_id":"s1","hook_event_name":"WorktreeRemove"}'
assert_exit "a payload with no worktree_path refuses" 1 "$RC"

assert_real_worktree_root_clean "$TEST_TMPDIR"

[[ $FAILED -eq 0 ]] || exit 1
