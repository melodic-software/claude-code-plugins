#!/usr/bin/env bash
# Black-box contract tests for cache-content-check.sh (self-contained — ships
# with the plugin). Fixtures are built per-case into a temp dir: a throwaway git
# repo standing in for a marketplace's installLocation at two commits, a fake
# cache directory, and CACHE_CONTENT_* state files pointing at both. Mirrors
# fleet-state.test.sh's structure.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/cache-content-check.sh"
# Never /tmp: on Windows that is a drive-root path that accumulates silently.
# $TEMP there is a NATIVE path (`C:\Users\…\Temp`), and its backslashes would be
# embedded raw into the fixture JSON, where a backslash is an escape character —
# the state files would be malformed and every case would read as the script
# correctly rejecting schema drift. Folded to forward slashes, which Git Bash
# accepts everywhere, before anything is built under it.
TMP_BASE="${TMPDIR:-${TEMP:-/var/tmp}}"
TMP_BASE="${TMP_BASE//\\//}"
TEST_TMPDIR="$(mktemp -d "$TMP_BASE/cache-content-check.XXXXXX")"
TEST_TMPDIR="${TEST_TMPDIR//\\//}"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  printf 'PASS: %s\n' "$1"
}
fail() {
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
  *) fail "$1" "expected to contain: $3 — got: $2" ;;
  esac
}

# Discriminating skips: each names the single tool whose absence it excuses, so
# a green run on a host missing it is not read as a green run of these cases.
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — every case here parses the script's JSON body" >&2
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed — the script's whole compare is git plumbing" >&2
  exit 0
fi

# --- Fixture builders --------------------------------------------------------

# CASE_NUM must be incremented in the CALLER's shell before calling this, never
# inside it: `case_dir=$(new_case_dir)` runs in a subshell, so an assignment
# made in here is discarded and every case reuses case-1's directory.
new_case_dir() {
  local case_dir="$TEST_TMPDIR/case-$CASE_NUM"
  mkdir -p "$case_dir"
  echo "$case_dir"
}

write() {
  local path="$1" content="$2"
  mkdir -p "${path%/*}"
  printf '%s' "$content" >"$path"
}

# Builds the marketplace clone at TWO commits and echoes "<sha1> <sha2>".
#   commit 1: plugins/alpha/{hooks/run.sh, lib/util.sh, gone.txt}
#   commit 2: run.sh changed, gone.txt deleted, lib/new.sh added
# Both commits carry the same marketplace.json, so a version number that never
# moves — the exact condition issue #3681 turns on — is what the fixture models.
seed_market_repo() {
  local case_dir="$1" repo="$1/market"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config user.name fixture
  git -C "$repo" config commit.gpgsign false
  write "$repo/.claude-plugin/marketplace.json" \
    '{"plugins":[{"name":"alpha","source":"./plugins/alpha"}]}'
  write "$repo/.gitignore" 'plugins/alpha/generated/'
  write "$repo/plugins/alpha/hooks/run.sh" 'echo v1'
  write "$repo/plugins/alpha/lib/util.sh" 'echo util'
  write "$repo/plugins/alpha/gone.txt" 'removed at commit 2'
  git -C "$repo" add -A
  git -C "$repo" commit -q -m one
  local sha1
  sha1=$(git -C "$repo" rev-parse HEAD)

  write "$repo/plugins/alpha/hooks/run.sh" 'echo v2'
  rm -f "$repo/plugins/alpha/gone.txt"
  write "$repo/plugins/alpha/lib/new.sh" 'echo new'
  git -C "$repo" add -A
  git -C "$repo" commit -q -m two
  local sha2
  sha2=$(git -C "$repo" rev-parse HEAD)
  echo "$sha1 $sha2"
}

# Materializes the cache directory from a commit of the fixture repo, so "the
# cache holds commit N's build" is expressed as exactly that and never as a
# hand-copied approximation that could drift from what the commit contains.
seed_cache_from() {
  local case_dir="$1" sha="$2" repo="$1/market" cache="$1/cache/alpha/1.0.0"
  rm -rf "$cache"
  mkdir -p "$cache"
  local rel
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    mkdir -p "$cache/${rel#plugins/alpha/}" 2>/dev/null
    rmdir "$cache/${rel#plugins/alpha/}" 2>/dev/null
    mkdir -p "$(dirname "$cache/${rel#plugins/alpha/}")"
    git -C "$repo" show "$sha:$rel" >"$cache/${rel#plugins/alpha/}"
  done < <(git -C "$repo" ls-tree -r --name-only "$sha" -- plugins/alpha)
  echo "$cache"
}

# Args: case_dir, sha recorded on the install record, [scope], [projectPath]
seed_state() {
  local case_dir="$1" sha="$2" scope="${3:-user}" project_path="${4:-}"
  local extra=""
  [[ -z "$project_path" ]] || extra=",\"projectPath\":\"$project_path\""
  write "$case_dir/installed_plugins.json" "{
    \"version\": 1,
    \"plugins\": {
      \"alpha@market1\": [
        {\"scope\":\"$scope\",\"version\":\"1.0.0\",\"gitCommitSha\":\"$sha\",\"installPath\":\"$case_dir/cache/alpha/1.0.0\"$extra}
      ]
    }
  }"
  write "$case_dir/known_marketplaces.json" \
    "{\"market1\": {\"installLocation\": \"$case_dir/market\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
}

run_check() {
  local case_dir="$1"
  shift
  env \
    CACHE_CONTENT_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    CACHE_CONTENT_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    bash "$SCRIPT" "$@" 2>&1
}

# Same run with stdout kept clean of stderr, for the cases that assert the
# "a rejection leaves stdout EMPTY" half of the --ids contract.
run_check_stdout() {
  local case_dir="$1"
  shift
  env \
    CACHE_CONTENT_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    CACHE_CONTENT_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    bash "$SCRIPT" "$@"
}

# ============================================================================
# Case: the cache holds exactly the recorded sha's build → match
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA2" >/dev/null
seed_state "$case_dir" "$SHA2"
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "match: exit 0" 0 "$rc"
assert_eq "match: one install checked" "1" "$(jq -r '.checked' <<<"$out" 2>/dev/null)"
assert_eq "match: verdict is match" "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "match: the match tally counts it" "1" "$(jq -r '.match' <<<"$out" 2>/dev/null)"
assert_eq "match: nothing is reported stale" "0" "$(jq -r '.stale_content' <<<"$out" 2>/dev/null)"
assert_eq "match: the record carries its recorded sha back" "$SHA2" "$(jq -r '.installs[0].gitCommitSha' <<<"$out" 2>/dev/null)"

# ============================================================================
# Case: the cache holds the OLDER commit's build while the record's sha points
# at the newer one. This is issue #3681's exact shape, and the version number
# is identical across both commits, so a version-and-sha check sees nothing.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA1" >/dev/null
seed_state "$case_dir" "$SHA2"
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "stale: exit 0 — a finding is not an error" 0 "$rc"
assert_eq "stale: verdict is stale-content" "stale-content" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "stale: the stale tally counts it" "1" "$(jq -r '.stale_content' <<<"$out" 2>/dev/null)"
assert_eq "stale: the changed file is counted as differing" "1" "$(jq -r '.installs[0].differing' <<<"$out" 2>/dev/null)"
assert_contains "stale: the changed file is named" "$(jq -r '.installs[0].paths | join(",")' <<<"$out" 2>/dev/null)" "differs: hooks/run.sh"
assert_eq "stale: the file added at the newer sha is missing from the cache" "1" "$(jq -r '.installs[0].missing_from_cache' <<<"$out" 2>/dev/null)"
assert_contains "stale: that missing file is named" "$(jq -r '.installs[0].paths | join(",")' <<<"$out" 2>/dev/null)" "missing-from-cache: lib/new.sh"
# The same fixture carries the deletion half: gone.txt exists at SHA1, which is
# what the cache was built from, and not at SHA2.
assert_eq "stale: a file deleted at the recorded sha but still in the cache is counted" "1" "$(jq -r '.installs[0].extra_in_cache' <<<"$out" 2>/dev/null)"
assert_contains "stale: that leftover file is named" "$(jq -r '.installs[0].paths | join(",")' <<<"$out" 2>/dev/null)" "extra-in-cache: gone.txt"
# An untouched file must NOT be swept into the finding — the report is read as
# a list of files to look at, so a false name in it costs the operator a read.
assert_eq "stale: an unchanged file is not reported" "" "$(jq -r '[.installs[].paths[] | select(test("util.sh"))] | join(",")' <<<"$out" 2>/dev/null)"

# ============================================================================
# Case: --ids emits only the stale-content ids, and emits them CR-free. Same
# fixture as above, so the id it emits is one the JSON body verdicts stale.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
ids=$(run_check_stdout "$case_dir" --marketplace market1 --ids 2>/dev/null)
rc=$?
assert_exit "--ids: exit 0" 0 "$rc"
assert_eq "--ids: emits the stale id, fully qualified" "alpha@market1" "$ids"
cr_free=$(printf '%s' "$ids" | tr -d '\r')
assert_eq "--ids: the id carries no carriage return" "$ids" "$cr_free"

# ...and a matching fleet emits nothing at all, which is success, not an error.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA2" >/dev/null
seed_state "$case_dir" "$SHA2"
ids=$(run_check_stdout "$case_dir" --marketplace market1 --ids 2>/dev/null)
rc=$?
assert_exit "--ids: a clean fleet is exit 0" 0 "$rc"
assert_eq "--ids: a clean fleet emits nothing" "" "$ids"

# ============================================================================
# Case: the recorded sha is not an object in the installLocation clone. The
# check must say so and must NOT fetch — a fetch is a network mutation, and it
# would silently repair the very condition being reported.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA2" >/dev/null
seed_state "$case_dir" "0123456789abcdef0123456789abcdef01234567"
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "sha-not-local: exit 0" 0 "$rc"
assert_eq "sha-not-local: verdict names the condition" "sha-not-local" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "sha-not-local: counted as unverifiable, not as a match" "1" "$(jq -r '.unverifiable' <<<"$out" 2>/dev/null)"
assert_eq "sha-not-local: and not as a match" "0" "$(jq -r '.match' <<<"$out" 2>/dev/null)"

# ============================================================================
# Case: a cache-only file the marketplace's own .gitignore covers is generated
# state, not a stale build. Without this filter a live plugin root reports
# stale on its own __pycache__ / node_modules.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
cache=$(seed_cache_from "$case_dir" "$SHA2")
seed_state "$case_dir" "$SHA2"
write "$cache/generated/artifact.bin" 'generated at run time'
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "gitignored extra: still a match" "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "gitignored extra: not counted as extra" "0" "$(jq -r '.installs[0].extra_in_cache' <<<"$out" 2>/dev/null)"
# A cache-only file the repo does NOT ignore is still a finding, so the filter
# above is a filter and not a blanket amnesty for every extra file.
write "$cache/leftover.txt" 'not ignored anywhere'
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "unignored extra: is stale-content" "stale-content" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_contains "unignored extra: is named" "$(jq -r '.installs[0].paths | join(",")' <<<"$out" 2>/dev/null)" "extra-in-cache: leftover.txt"

# ============================================================================
# Case: `.in_use` is Claude Code's own per-process refcount directory. It is in
# every cache version directory and in no commit; counting it would report the
# entire fleet stale on its existence alone.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
cache=$(seed_cache_from "$case_dir" "$SHA2")
seed_state "$case_dir" "$SHA2"
write "$cache/.in_use/12345" ''
out=$(run_check "$case_dir" --marketplace market1)
assert_eq ".in_use: does not make the install stale" "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"

# ============================================================================
# Case: a project-scope record whose projectPath is not present on this machine
# is skipped and COUNTED, never verdicted. Absent is not dead: an unmounted
# volume and a removed worktree are indistinguishable to a directory test.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA2" >/dev/null
seed_state "$case_dir" "$SHA2" project "$case_dir/no-such-repo"
out=$(run_check "$case_dir" --marketplace market1 --scope project)
rc=$?
assert_exit "absent projectPath: exit 0" 0 "$rc"
assert_eq "absent projectPath: counted as skipped" "1" "$(jq -r '.skipped_absent_project_paths' <<<"$out" 2>/dev/null)"
assert_eq "absent projectPath: not counted as checked" "0" "$(jq -r '.checked' <<<"$out" 2>/dev/null)"
assert_eq "absent projectPath: emits no install record" "0" "$(jq -r '.installs | length' <<<"$out" 2>/dev/null)"
# The same record with a present directory IS checked, so the skip is keyed on
# presence and not on the scope.
mkdir -p "$case_dir/present-repo"
seed_state "$case_dir" "$SHA2" project "$case_dir/present-repo"
out=$(run_check "$case_dir" --marketplace market1 --scope project)
assert_eq "present projectPath: checked" "1" "$(jq -r '.checked' <<<"$out" 2>/dev/null)"
assert_eq "present projectPath: nothing skipped" "0" "$(jq -r '.skipped_absent_project_paths' <<<"$out" 2>/dev/null)"
# ...and the default scope is `user`, so neither record appears without --scope.
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "default scope is user: a project record is out of scope" "0" "$(jq -r '.checked' <<<"$out" 2>/dev/null)"
assert_eq "default scope is reported back" "user" "$(jq -r '.scope' <<<"$out" 2>/dev/null)"

# ============================================================================
# Case: the installLocation is a directory but not a git work tree. There is no
# tree to compare against, and that is a stated verdict, never a silent match.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA2" >/dev/null
seed_state "$case_dir" "$SHA2"
mkdir -p "$case_dir/plain"
write "$case_dir/known_marketplaces.json" \
  "{\"market1\": {\"installLocation\": \"$case_dir/plain\"}}"
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "not-a-git-worktree: verdict names the condition" "not-a-git-worktree" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "not-a-git-worktree: counted as unverifiable" "1" "$(jq -r '.unverifiable' <<<"$out" 2>/dev/null)"

# ...and an installLocation that is not on this machine at all is its own
# verdict, distinct from a directory that exists and is not a repo.
CASE_NUM=$((CASE_NUM + 1))
write "$case_dir/known_marketplaces.json" \
  "{\"market1\": {\"installLocation\": \"$case_dir/does-not-exist\"}}"
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "no-install-location: verdict names the condition" "no-install-location" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"

# ============================================================================
# Case: the cache directory itself is gone. Reported, never treated as a match.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_state "$case_dir" "$SHA2"
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "install-path-missing: verdict names the condition" "install-path-missing" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"

# ============================================================================
# Case: malformed installed_plugins.json fails LOUD. Read leniently it would
# yield an empty install list, which is indistinguishable from a clean fleet —
# the one wrong answer this check must never give.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_state "$case_dir" "$SHA2"
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":'
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "malformed installed_plugins.json: exit 2" 2 "$rc"
assert_contains "malformed installed_plugins.json: the error names the file" "$out" "installed_plugins.json"
# Structurally-valid JSON of the WRONG SHAPE is refused too, not just a parse
# error: `.plugins` holding anything but a map of arrays is schema drift.
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":{"scope":"user"}}}'
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "wrong-shape installed_plugins.json: exit 2" 2 "$rc"

# ============================================================================
# Case: an unknown marketplace is a usage error and names itself. Deliberately
# exit 2 rather than fleet-state.sh's exit 1 for an unresolvable marketplace:
# the name came from the caller's own argument.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA2" >/dev/null
seed_state "$case_dir" "$SHA2"
out=$(run_check "$case_dir" --marketplace nosuchmarket)
rc=$?
assert_exit "unknown marketplace: exit 2" 2 "$rc"
assert_contains "unknown marketplace: the error names it" "$out" "nosuchmarket"
stdout_only=$(run_check_stdout "$case_dir" --marketplace nosuchmarket 2>/dev/null)
assert_eq "unknown marketplace: stdout is left empty" "" "$stdout_only"

# ============================================================================
# Case: usage rejections. Each leaves stdout EMPTY, so a `< <(… --ids …)`
# consumer — which cannot see the process's exit status — can never read an
# error line as a plugin id.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
out=$(run_check "$case_dir" --all --ids)
rc=$?
assert_exit "--ids with --all: exit 2" 2 "$rc"
assert_contains "--ids with --all: the error says why" "$out" "--ids cannot be combined with --all"
assert_eq "--ids with --all: stdout is left empty" "" "$(run_check_stdout "$case_dir" --all --ids 2>/dev/null)"

out=$(run_check "$case_dir")
rc=$?
assert_exit "no target: exit 2" 2 "$rc"
assert_contains "no target: the error names the required flags" "$out" "--marketplace"

out=$(run_check "$case_dir" --marketplace market1 --scope sideways)
rc=$?
assert_exit "unknown scope: exit 2" 2 "$rc"
assert_contains "unknown scope: the error names the accepted values" "$out" "user, project, or all"

out=$(run_check "$case_dir" --marketplace)
rc=$?
assert_exit "--marketplace with no name: exit 2, and does not spin" 2 "$rc"

out=$(run_check "$case_dir" --nonsense)
rc=$?
assert_exit "unknown argument: exit 2" 2 "$rc"

# ============================================================================
# Case: --all sweeps every marketplace, and a per-marketplace failure is
# reported inline rather than aborting the sweep.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA2" >/dev/null
seed_state "$case_dir" "$SHA2"
write "$case_dir/known_marketplaces.json" \
  "{\"market1\": {\"installLocation\": \"$case_dir/market\"}, \"market2\": {\"installLocation\": \"$case_dir/absent\"}}"
out=$(run_check "$case_dir" --all)
rc=$?
assert_exit "--all: exit 0" 0 "$rc"
assert_eq "--all: both marketplaces appear in the envelope" "2" "$(jq -r '.marketplaces | length' <<<"$out" 2>/dev/null)"
assert_eq "--all: the healthy marketplace still reports its match" "match" "$(jq -r '.marketplaces.market1.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "--all: a marketplace with no installs is still reported" "0" "$(jq -r '.marketplaces.market2.checked' <<<"$out" 2>/dev/null)"

# ============================================================================
# Case: the script writes NOTHING. That is its whole contract — it is the audit
# that must never repair the condition it reports — so both the cache directory
# and the marketplace clone are hash-compared across a full run.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA1" >/dev/null
seed_state "$case_dir" "$SHA2"
snapshot() {
  find "$case_dir/cache" "$case_dir/market" -type f 2>/dev/null | sort |
    while IFS= read -r f; do printf '%s %s\n' "$f" "$(git hash-object "$f" 2>/dev/null)"; done
}
before=$(snapshot)
run_check "$case_dir" --marketplace market1 >/dev/null 2>&1
after=$(snapshot)
assert_eq "read-only: no file under the cache or the clone changed" "$before" "$after"
git_status=$(git -C "$case_dir/market" status --porcelain 2>&1)
assert_eq "read-only: the marketplace clone's work tree is still clean" "" "$git_status"
assert_eq "read-only: the clone's HEAD did not move" "$SHA2" "$(git -C "$case_dir/market" rev-parse HEAD)"

# ============================================================================
# Process budget: a clean install costs a FIXED number of process creations,
# never one per file. Each creation is a fork() emulation plus a CreateProcess
# on Windows Git Bash (roughly 120 ms on a quiet host, seconds on a contended
# one), and the obvious implementation of this check — hash each cache file on
# its own — would pay one for every file in every plugin, which for a plugin
# that vendors dependencies is thousands. The batched `git hash-object
# --stdin-paths` is what keeps it flat, and the per-file `--path` re-hash is
# reached only for a file that already looks different. Counted the way
# fleet-state.test.sh counts it: `bash -x` with PS4 carrying $BASHPID, so every
# subshell shows up as a distinct pid, plus every external exec. Two fixtures
# differing only in FILE COUNT must cost the same.
# ============================================================================
count_creations() {
  local trace="$1" forks execs
  forks=$(grep -oE '^\++[0-9]+\+' "$trace" | sort -u | wc -l | tr -d ' ')
  execs=$(grep -cE '^\++[0-9]+\+ (command )?(jq|git|find|tr|realpath|readlink|mktemp|head|sed|cat|grep|awk|sort|uniq|cut|wc|date|dirname|basename|ls) ' "$trace" || true)
  echo $((forks - 1 + execs))
}

# Builds a one-commit fixture whose plugin holds $2 files, with the cache an
# exact copy of it, so every case here is a clean `match` and the only variable
# is how many files that match covers.
seed_budget_case() {
  local case_dir="$1" n="$2" repo="$1/market" i
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config user.name fixture
  git -C "$repo" config commit.gpgsign false
  write "$repo/.claude-plugin/marketplace.json" \
    '{"plugins":[{"name":"alpha","source":"./plugins/alpha"}]}'
  for ((i = 1; i <= n; i++)); do
    write "$repo/plugins/alpha/file$i.sh" "echo $i"
  done
  git -C "$repo" add -A
  git -C "$repo" commit -q -m one
  seed_cache_from "$case_dir" "$(git -C "$repo" rev-parse HEAD)" >/dev/null
  seed_state "$case_dir" "$(git -C "$repo" rev-parse HEAD)"
}

run_traced() {
  local case_dir="$1" trace="$2"
  # shellcheck disable=SC2016  # PS4 must reach bash unexpanded: bash expands it per traced line
  env \
    CACHE_CONTENT_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    CACHE_CONTENT_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    PS4='+${BASHPID}+ ' \
    bash -x "$SCRIPT" --marketplace market1 2>"$trace"
}

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_budget_case "$case_dir" 2
out=$(run_traced "$case_dir" "$case_dir/trace-small.log")
small=$(count_creations "$case_dir/trace-small.log")
assert_eq "process budget: the two-file run still reports a match" \
  "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_budget_case "$case_dir" 30
out=$(run_traced "$case_dir" "$case_dir/trace-large.log")
large=$(count_creations "$case_dir/trace-large.log")
assert_eq "process budget: the thirty-file run still reports a match" \
  "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "process budget: the count does not grow with the file count (2 files vs 30)" \
  "$small" "$large"
if [[ "$large" -le 24 ]]; then
  pass "process budget: a one-install report costs at most 24 process creations (measured $large)"
else
  fail "process budget: a one-install report costs at most 24 process creations" \
    "measured $large (trace: $case_dir/trace-large.log)"
fi

# --- Summary -------------------------------------------------------------
printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] && exit 0
exit 1
