#!/usr/bin/env bash
# test-scope: .gitattributes
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/cache-content-check.sh"
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

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — every case here parses the script's JSON body" >&2
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed — the script's whole compare is git plumbing" >&2
  exit 0
fi

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

init_fixture_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config user.name fixture
  git -C "$repo" config commit.gpgsign false
}

seed_market_repo() {
  local case_dir="$1" repo="$1/market"
  init_fixture_repo "$repo"
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

seed_cache_from() {
  local case_dir="$1" sha="$2" repo="$1/market" cache="$1/cache/alpha/1.0.0"
  rm -rf "$cache"
  mkdir -p "$cache"
  local rel
  while IFS= read -r -d '' rel; do
    [[ -n "$rel" ]] || continue
    mkdir -p "$(dirname "$cache/${rel#plugins/alpha/}")"
    git -C "$repo" show "$sha:$rel" >"$cache/${rel#plugins/alpha/}"
  done < <(git -C "$repo" ls-tree -r -z --name-only "$sha" -- plugins/alpha)
  echo "$cache"
}

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

run_check_stdout() {
  local case_dir="$1"
  shift
  env \
    CACHE_CONTENT_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    CACHE_CONTENT_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    bash "$SCRIPT" "$@"
}

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
assert_eq "stale: a file deleted at the recorded sha but still in the cache is counted" "1" "$(jq -r '.installs[0].extra_in_cache' <<<"$out" 2>/dev/null)"
assert_contains "stale: that leftover file is named" "$(jq -r '.installs[0].paths | join(",")' <<<"$out" 2>/dev/null)" "extra-in-cache: gone.txt"
assert_eq "stale: an unchanged file is not reported" "" "$(jq -r '[.installs[].paths[] | select(test("util.sh"))] | join(",")' <<<"$out" 2>/dev/null)"
assert_eq "stale: no .changes/alpha/ in the clone, so no unreleased changes" "false" "$(jq -r '.installs[0].unreleased_changes' <<<"$out" 2>/dev/null)"
write "$case_dir/market/.changes/alpha/feat-x-0123abcd.md" $'---\nbump: patch\n---\n\n### Fixed\n\n- x\n'
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "stale with fragments: still stale-content" "stale-content" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "stale with fragments: marked unreleased_changes" "true" "$(jq -r '.installs[0].unreleased_changes' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
ids=$(run_check_stdout "$case_dir" --marketplace market1 --ids 2>/dev/null)
rc=$?
assert_exit "--ids: exit 0" 0 "$rc"
assert_eq "--ids: emits the stale id, fully qualified" "alpha@market1" "$ids"
cr_free=$(printf '%s' "$ids" | tr -d '\r')
assert_eq "--ids: the id carries no carriage return" "$ids" "$cr_free"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA2" >/dev/null
seed_state "$case_dir" "$SHA2"
ids=$(run_check_stdout "$case_dir" --marketplace market1 --ids 2>/dev/null)
rc=$?
assert_exit "--ids: a clean fleet is exit 0" 0 "$rc"
assert_eq "--ids: a clean fleet emits nothing" "" "$ids"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA2" >/dev/null
seed_state "$case_dir" "0123456789abcdef0123456789abcdef01234567"
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "sha absent from the clone: exit 0" 0 "$rc"
assert_eq "sha absent from the clone: verdict is not-at-head" "not-at-head" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "sha absent from the clone: counted not_checked" "1" "$(jq -r '.not_checked' <<<"$out" 2>/dev/null)"
assert_eq "sha absent from the clone: not counted unverifiable" "0" "$(jq -r '.unverifiable' <<<"$out" 2>/dev/null)"
assert_eq "sha absent from the clone: and not as a match" "0" "$(jq -r '.match' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA2" >/dev/null
shallow_url="file://$case_dir/market"
[[ "$case_dir" == /* ]] || shallow_url="file:///$case_dir/market"
git clone -q --depth 1 "$shallow_url" "$case_dir/shallow" 2>/dev/null
assert_eq "one-commit clone: the fixture clone's HEAD is the newer sha" "$SHA2" \
  "$(git -C "$case_dir/shallow" rev-parse HEAD 2>/dev/null)"
if git -C "$case_dir/shallow" cat-file -e "$SHA1^{commit}" 2>/dev/null; then
  fail "one-commit clone: the fixture clone lacks the older sha" "the clone holds $SHA1, so it is not one commit deep"
else
  pass "one-commit clone: the fixture clone lacks the older sha"
fi
mkdir -p "$case_dir/cache/alpha/0.9.0" "$case_dir/present-repo"
write "$case_dir/cache/alpha/0.9.0/hooks/run.sh" 'echo v1'
write "$case_dir/installed_plugins.json" "{
  \"version\": 1,
  \"plugins\": {
    \"alpha@market1\": [
      {\"scope\":\"user\",\"version\":\"1.0.0\",\"gitCommitSha\":\"$SHA2\",\"installPath\":\"$case_dir/cache/alpha/1.0.0\"},
      {\"scope\":\"project\",\"version\":\"0.9.0\",\"gitCommitSha\":\"$SHA1\",\"installPath\":\"$case_dir/cache/alpha/0.9.0\",\"projectPath\":\"$case_dir/present-repo\"}
    ]
  }
}"
write "$case_dir/known_marketplaces.json" \
  "{\"market1\": {\"installLocation\": \"$case_dir/shallow\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
out=$(run_check "$case_dir" --marketplace market1 --scope all)
rc=$?
assert_exit "one-commit clone: exit 0" 0 "$rc"
assert_eq "one-commit clone: both records checked" "2" "$(jq -r '.checked' <<<"$out" 2>/dev/null)"
assert_eq "one-commit clone: the record at HEAD is compared and matches" "match" \
  "$(jq -r --arg s "$SHA2" 'first(.installs[] | select(.gitCommitSha == $s) | .verdict)' <<<"$out" 2>/dev/null)"
assert_eq "one-commit clone: the record at the older sha is not-at-head" "not-at-head" \
  "$(jq -r --arg s "$SHA1" 'first(.installs[] | select(.gitCommitSha == $s) | .verdict)' <<<"$out" 2>/dev/null)"
assert_eq "one-commit clone: no file of the older record is compared" "0 0 0 0" \
  "$(jq -r --arg s "$SHA1" 'first(.installs[] | select(.gitCommitSha == $s) | "\(.differing) \(.missing_from_cache) \(.extra_in_cache) \(.paths | length)")' <<<"$out" 2>/dev/null)"
assert_eq "one-commit clone: tallies are 1 match, 1 not checked, 0 unverifiable, 0 stale" "1 1 0 0" \
  "$(jq -r '"\(.match) \(.not_checked) \(.unverifiable) \(.stale_content)"' <<<"$out" 2>/dev/null)"
write "$case_dir/cache/alpha/1.0.0/hooks/run.sh" 'echo edited'
out=$(run_check "$case_dir" --marketplace market1 --scope all)
assert_eq "one-commit clone: an edited cache at HEAD is still stale-content" "stale-content" \
  "$(jq -r --arg s "$SHA2" 'first(.installs[] | select(.gitCommitSha == $s) | .verdict)' <<<"$out" 2>/dev/null)"
assert_eq "one-commit clone: the older record stays not-at-head" "not-at-head" \
  "$(jq -r --arg s "$SHA1" 'first(.installs[] | select(.gitCommitSha == $s) | .verdict)' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
cache=$(seed_cache_from "$case_dir" "$SHA2")
seed_state "$case_dir" "$SHA2"
write "$cache/generated/artifact.bin" 'generated at run time'
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "gitignored extra: still a match" "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "gitignored extra: not counted as extra" "0" "$(jq -r '.installs[0].extra_in_cache' <<<"$out" 2>/dev/null)"
write "$cache/leftover.txt" 'not ignored anywhere'
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "unignored extra: is stale-content" "stale-content" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_contains "unignored extra: is named" "$(jq -r '.installs[0].paths | join(",")' <<<"$out" 2>/dev/null)" "extra-in-cache: leftover.txt"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
cache=$(seed_cache_from "$case_dir" "$SHA2")
seed_state "$case_dir" "$SHA2"
write "$cache/.in_use/12345" ''
out=$(run_check "$case_dir" --marketplace market1)
assert_eq ".in_use: does not make the install stale" "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"

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
mkdir -p "$case_dir/present-repo"
seed_state "$case_dir" "$SHA2" project "$case_dir/present-repo"
out=$(run_check "$case_dir" --marketplace market1 --scope project)
assert_eq "present projectPath: checked" "1" "$(jq -r '.checked' <<<"$out" 2>/dev/null)"
assert_eq "present projectPath: nothing skipped" "0" "$(jq -r '.skipped_absent_project_paths' <<<"$out" 2>/dev/null)"
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "default scope is user: a project record is out of scope" "0" "$(jq -r '.checked' <<<"$out" 2>/dev/null)"
assert_eq "default scope is reported back" "user" "$(jq -r '.scope' <<<"$out" 2>/dev/null)"

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

CASE_NUM=$((CASE_NUM + 1))
write "$case_dir/known_marketplaces.json" \
  "{\"market1\": {\"installLocation\": \"$case_dir/does-not-exist\"}}"
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "no-install-location: verdict names the condition" "no-install-location" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
init_fixture_repo "$case_dir/unborn"
write "$case_dir/known_marketplaces.json" \
  "{\"market1\": {\"installLocation\": \"$case_dir/unborn\"}}"
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "no-clone-head: verdict names the condition" "no-clone-head" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "no-clone-head: counted unverifiable, not not_checked" "1 0" \
  "$(jq -r '"\(.unverifiable) \(.not_checked)"' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_state "$case_dir" "$SHA2"
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "install-path-missing: verdict names the condition" "install-path-missing" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_state "$case_dir" "$SHA2"
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":'
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "malformed installed_plugins.json: exit 2" 2 "$rc"
assert_contains "malformed installed_plugins.json: the error names the file" "$out" "installed_plugins.json"
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":{"scope":"user"}}}'
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "wrong-shape installed_plugins.json: exit 2" 2 "$rc"

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
assert_contains "unknown argument: names --help" "$out" "(see --help)"

nojq_bin="$case_dir/nojq-bin"
mkdir -p "$nojq_bin"
ln -s "$(command -v bash)" "$nojq_bin/bash" 2>/dev/null
if [[ -L "$nojq_bin/bash" ]] && [[ "$(env PATH="$nojq_bin" "$nojq_bin/bash" -c 'echo ok' 2>/dev/null)" == "ok" ]]; then
  out=$(env PATH="$nojq_bin" "$nojq_bin/bash" "$SCRIPT" --help 2>&1)
  rc=$?
  assert_exit "--help without jq or git: exit 0" 0 "$rc"
  assert_contains "--help lists the exit codes" "$out" "Exit: 0 ran to completion"
  out=$(env PATH="$nojq_bin" "$nojq_bin/bash" "$SCRIPT" --all 2>&1)
  rc=$?
  assert_exit "run without jq: exit 2" 2 "$rc"
  assert_contains "run without jq: actionable notice" "$out" "jq required"
else
  printf 'SKIP: no-jq cases — ln -s cannot make a runnable link on this host (Windows without the symlink privilege)\n' >&2
fi

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

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA2" >/dev/null
seed_state "$case_dir" "$SHA2"
write "$case_dir/installed_plugins.json" "{
  \"version\": 1,
  \"plugins\": {
    \"alpha@market1\": [
      {\"scope\":\"user\",\"version\":\"1.0.0\",\"installPath\":\"$case_dir/cache/alpha/1.0.0\"}
    ]
  }
}"
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "absent gitCommitSha: exit 0" 0 "$rc"
assert_eq "absent gitCommitSha: verdict names the missing field" \
  "no-git-commit-sha" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "absent gitCommitSha: the sha comes back empty, never fabricated" \
  "" "$(jq -r '.installs[0].gitCommitSha' <<<"$out" 2>/dev/null)"
assert_eq "absent gitCommitSha: the installPath did not slide into another column" \
  "$case_dir/cache/alpha/1.0.0" "$(jq -r '.installs[0].installPath' <<<"$out" 2>/dev/null)"
assert_eq "absent gitCommitSha: counted as unverifiable" "1" "$(jq -r '.unverifiable' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
repo="$case_dir/market"
init_fixture_repo "$repo"
write "$repo/.claude-plugin/marketplace.json" \
  '{"plugins":[{"name":"alpha","source":"./plugins/alpha"}]}'
write "$repo/plugins/alpha/hooks/run.sh" 'echo v1'
write "$repo/plugins/alpha/lib/util.sh" 'echo util'
git -C "$repo" add -A
git -C "$repo" commit -q -m one
RENAME_SHA1=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" mv plugins/alpha plugins/alpha-renamed
write "$repo/.claude-plugin/marketplace.json" \
  '{"plugins":[{"name":"alpha","source":"./plugins/alpha-renamed"}]}'
git -C "$repo" add -A
git -C "$repo" commit -q -m rename
cache="$case_dir/cache/alpha/1.0.0"
mkdir -p "$cache/hooks" "$cache/lib"
git -C "$repo" show "$RENAME_SHA1:plugins/alpha/hooks/run.sh" >"$cache/hooks/run.sh"
git -C "$repo" show "$RENAME_SHA1:plugins/alpha/lib/util.sh" >"$cache/lib/util.sh"
seed_state "$case_dir" "$RENAME_SHA1"
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "renamed source: exit 0" 0 "$rc"
assert_eq "renamed source: a record older than the clone's HEAD is not-at-head, never stale-content" \
  "not-at-head" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
git -C "$repo" checkout -q --detach "$RENAME_SHA1"
write "$repo/.claude-plugin/marketplace.json" \
  '{"plugins":[{"name":"alpha","source":"./plugins/alpha-renamed"}]}'
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "renamed source: at HEAD, the source path is read at the recorded sha, so it is a match" \
  "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "renamed source: nothing is called extra-in-cache" \
  "0" "$(jq -r '.installs[0].extra_in_cache' <<<"$out" 2>/dev/null)"
assert_eq "renamed source: nothing is called missing-from-cache" \
  "0" "$(jq -r '.installs[0].missing_from_cache' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
repo="$case_dir/market"
init_fixture_repo "$repo"
write "$repo/.claude-plugin/marketplace.json" \
  '{"plugins":[{"name":"alpha","source":"./plugins/ghost"}]}'
write "$repo/plugins/other/keep.txt" 'unrelated'
git -C "$repo" add -A
git -C "$repo" commit -q -m ghost
GHOST_SHA=$(git -C "$repo" rev-parse HEAD)
cache="$case_dir/cache/alpha/1.0.0"
mkdir -p "$cache"
write "$cache/whatever.sh" 'echo hi'
seed_state "$case_dir" "$GHOST_SHA"
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "no-source-at-sha: exit 0" 0 "$rc"
assert_eq "no-source-at-sha: verdict names the condition" \
  "no-source-at-sha" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "no-source-at-sha: counted as unverifiable" "1" "$(jq -r '.unverifiable' <<<"$out" 2>/dev/null)"
assert_eq "no-source-at-sha: not counted as stale" "0" "$(jq -r '.stale_content' <<<"$out" 2>/dev/null)"
assert_eq "no-source-at-sha: no cache file is called extra" "0" "$(jq -r '.installs[0].extra_in_cache' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
repo="$case_dir/market"
init_fixture_repo "$repo"
write "$repo/.claude-plugin/marketplace.json" \
  '{"plugins":[{"name":"alpha","source":"./plugins/alpha"}]}'
write "$repo/plugins/alpha/plain.sh" 'echo plain'
write "$repo/plugins/alpha/café.txt" 'accented'
git -C "$repo" add -A
git -C "$repo" commit -q -m one
NONASCII_SHA=$(git -C "$repo" rev-parse HEAD)
seed_cache_from "$case_dir" "$NONASCII_SHA" >/dev/null
seed_state "$case_dir" "$NONASCII_SHA"
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "non-ASCII path: exit 0" 0 "$rc"
assert_eq "non-ASCII path: an unchanged accented filename is a match, not a finding" \
  "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "non-ASCII path: it is not reported missing from the cache" \
  "0" "$(jq -r '.installs[0].missing_from_cache' <<<"$out" 2>/dev/null)"
assert_eq "non-ASCII path: nor extra in the cache" \
  "0" "$(jq -r '.installs[0].extra_in_cache' <<<"$out" 2>/dev/null)"
printf '%s' 'edited' >"$case_dir/cache/alpha/1.0.0/café.txt"
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "non-ASCII path: an edited accented file is still stale-content" \
  "stale-content" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "non-ASCII path: and is counted as differing, not as missing+extra" \
  "1" "$(jq -r '.installs[0].differing' <<<"$out" 2>/dev/null)"

seed_odd_names_case() {
  local case_dir="$1" repo="$1/market" name rel odd_sha
  shift
  init_fixture_repo "$repo"
  write "$repo/.claude-plugin/marketplace.json" \
    '{"plugins":[{"name":"alpha","source":"./plugins/alpha"}]}'
  write "$repo/plugins/alpha/plain.sh" 'echo plain'
  for name in "$@"; do
    printf '%s' "content of $name" 2>/dev/null >"$repo/plugins/alpha/$name" || return 1
  done
  git -C "$repo" add -A 2>/dev/null || return 1
  git -C "$repo" commit -q -m odd-names 2>/dev/null || return 1
  local -A tracked_names=()
  while IFS= read -r -d '' rel; do
    tracked_names["$rel"]=1
  done < <(git -C "$repo" ls-tree -r -z --name-only HEAD -- plugins/alpha)
  for name in "$@"; do
    [[ -n "${tracked_names["plugins/alpha/$name"]+set}" ]] || return 1
  done
  odd_sha=$(git -C "$repo" rev-parse HEAD)
  seed_cache_from "$case_dir" "$odd_sha" >/dev/null
  seed_state "$case_dir" "$odd_sha"
}

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
if ! seed_odd_names_case "$case_dir" 'sp ace.sh' $'tab\there.sh' 'star*.sh'; then
  printf 'SKIP: space/tab/glob path case — this host cannot track those filenames as spelled\n' >&2
else
  cache="$case_dir/cache/alpha/1.0.0"
  out=$(run_check "$case_dir" --marketplace market1)
  rc=$?
  assert_exit "space/tab/glob path: exit 0" 0 "$rc"
  assert_eq "space/tab/glob path: unchanged files are a match" \
    "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
  assert_eq "space/tab/glob path: nothing missing, extra or differing" "0 0 0" \
    "$(jq -r '.installs[0] | "\(.missing_from_cache) \(.extra_in_cache) \(.differing)"' <<<"$out" 2>/dev/null)"
  write "$cache/stark.sh" 'not tracked'
  out=$(run_check "$case_dir" --marketplace market1)
  assert_eq "space/tab/glob path: a cache-only file beside star*.sh is stale-content" \
    "stale-content" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
  assert_eq "space/tab/glob path: that file is counted once, with nothing else reported" "0 1 0" \
    "$(jq -r '.installs[0] | "\(.missing_from_cache) \(.extra_in_cache) \(.differing)"' <<<"$out" 2>/dev/null)"
  rm -f "$cache/stark.sh"
  rm -f "$cache/sp ace.sh"
  out=$(run_check "$case_dir" --marketplace market1)
  assert_eq "space/tab/glob path: a file with a space deleted from the cache is stale-content" \
    "stale-content" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
  assert_eq "space/tab/glob path: it is one missing file, not split into extras" "1 0 0" \
    "$(jq -r '.installs[0] | "\(.missing_from_cache) \(.extra_in_cache) \(.differing)"' <<<"$out" 2>/dev/null)"
  assert_contains "space/tab/glob path: the missing file is named whole" \
    "$(jq -r '.installs[0].paths | join(",")' <<<"$out" 2>/dev/null)" "missing-from-cache: sp ace.sh"
fi

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
if ! seed_odd_names_case "$case_dir" $'nl\nname.sh' $'soh\x01name.sh' 'sp ace.sh' 'star*.sh'; then
  printf 'SKIP: newline/SOH path case — this host cannot track those filenames as spelled\n' >&2
else
  cache="$case_dir/cache/alpha/1.0.0"
  ODD_SHA=$(git -C "$case_dir/market" rev-parse HEAD)
  out=$(run_check "$case_dir" --marketplace market1)
  rc=$?
  assert_exit "newline/SOH path: exit 0" 0 "$rc"
  assert_eq "newline/SOH path: unchanged files are a match" \
    "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
  assert_eq "newline/SOH path: nothing missing, extra or differing" "0 0 0" \
    "$(jq -r '.installs[0] | "\(.missing_from_cache) \(.extra_in_cache) \(.differing)"' <<<"$out" 2>/dev/null)"
  rm -f "$cache/"$'nl\nname.sh'
  out=$(run_check "$case_dir" --marketplace market1)
  assert_eq "newline/SOH path: a newline file deleted from the cache is stale-content" \
    "stale-content" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
  assert_eq "newline/SOH path: it is one missing file, nothing else" "1 0 0" \
    "$(jq -r '.installs[0] | "\(.missing_from_cache) \(.extra_in_cache) \(.differing)"' <<<"$out" 2>/dev/null)"
  assert_eq "newline/SOH path: the missing file is named with its newline" \
    $'missing-from-cache: nl\nname.sh' "$(jq -r '.installs[0].paths[0]' <<<"$out" 2>/dev/null)"
  seed_cache_from "$case_dir" "$ODD_SHA" >/dev/null
  printf '%s' 'edited' >"$cache/"$'soh\x01name.sh'
  out=$(run_check "$case_dir" --marketplace market1)
  assert_eq "newline/SOH path: an edited SOH file is one differing file, not missing+extra" "0 0 1" \
    "$(jq -r '.installs[0] | "\(.missing_from_cache) \(.extra_in_cache) \(.differing)"' <<<"$out" 2>/dev/null)"
fi

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
repo="$case_dir/market"
init_fixture_repo "$repo"
write "$repo/.claude-plugin/marketplace.json" \
  '{"plugins":[{"name":"alpha","source":"./plugins/alpha"}]}'
write "$repo/plugins/alpha/real.sh" 'echo real'
symlink_ok=""
if ln -s real.sh "$repo/plugins/alpha/link.sh" 2>/dev/null && [[ -L "$repo/plugins/alpha/link.sh" ]]; then
  git -C "$repo" add -A
  git -C "$repo" commit -q -m one
  case "$(git -C "$repo" ls-tree -r HEAD -- plugins/alpha/link.sh)" in
  120000*) symlink_ok="yes" ;;
  *) symlink_ok="" ;;
  esac
fi
if [[ -z "$symlink_ok" ]]; then
  printf 'SKIP: symlink case — this host cannot create a git-recorded symlink (Windows without the privilege, or core.symlinks=false)\n' >&2
else
  SYM_SHA=$(git -C "$repo" rev-parse HEAD)
  cache="$case_dir/cache/alpha/1.0.0"
  mkdir -p "$cache"
  git -C "$repo" show "$SYM_SHA:plugins/alpha/real.sh" >"$cache/real.sh"
  ln -s real.sh "$cache/link.sh"
  seed_state "$case_dir" "$SYM_SHA"
  out=$(run_check "$case_dir" --marketplace market1)
  assert_eq "symlink: an unchanged tracked link is a match" \
    "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
  assert_eq "symlink: it is not reported missing from the cache" \
    "0" "$(jq -r '.installs[0].missing_from_cache' <<<"$out" 2>/dev/null)"
  rm -f "$cache/link.sh"
  ln -s elsewhere.sh "$cache/link.sh"
  out=$(run_check "$case_dir" --marketplace market1)
  assert_eq "symlink: a link retargeted in the cache is stale-content" \
    "stale-content" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
fi

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
seed_cache_from "$case_dir" "$SHA2" >/dev/null
seed_state "$case_dir" "$SHA2"
REAL_GIT="$(command -v git)"
mkdir -p "$case_dir/stub"
write "$case_dir/stub/git" "#!/usr/bin/env bash
case \"\$*\" in
*'hash-object --stdin-paths'*)
  '$REAL_GIT' \"\$@\" | head -n -1
  exit 0
  ;;
esac
exec '$REAL_GIT' \"\$@\"
"
chmod +x "$case_dir/stub/git"
STUB_PATH_ENTRY="$case_dir/stub"
if command -v cygpath >/dev/null 2>&1; then
  STUB_PATH_ENTRY="$(cygpath -u "$case_dir/stub")"
fi
out=$(env PATH="$STUB_PATH_ENTRY:$PATH" \
  CACHE_CONTENT_INSTALLED_JSON="$case_dir/installed_plugins.json" \
  CACHE_CONTENT_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
  bash "$SCRIPT" --marketplace market1 2>&1)
rc=$?
assert_exit "hash-batch-misaligned: exit 0" 0 "$rc"
assert_eq "hash-batch-misaligned: verdict names the broken contract" \
  "hash-batch-misaligned" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"
assert_eq "hash-batch-misaligned: counted as unverifiable" "1" "$(jq -r '.unverifiable' <<<"$out" 2>/dev/null)"
assert_eq "hash-batch-misaligned: not counted as stale" "0" "$(jq -r '.stale_content' <<<"$out" 2>/dev/null)"
assert_eq "hash-batch-misaligned: nothing is reported differing" \
  "0" "$(jq -r '.installs[0].differing' <<<"$out" 2>/dev/null)"
assert_eq "hash-batch-misaligned: nothing is reported missing from the cache" \
  "0" "$(jq -r '.installs[0].missing_from_cache' <<<"$out" 2>/dev/null)"
assert_eq "hash-batch-misaligned: nothing is reported extra in the cache" \
  "0" "$(jq -r '.installs[0].extra_in_cache' <<<"$out" 2>/dev/null)"
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "hash-batch-misaligned: the same fixture with the real git is a match" \
  "match" "$(jq -r '.installs[0].verdict' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
read -r SHA1 SHA2 <<<"$(seed_market_repo "$case_dir")"
write "$case_dir/market/plugins/alpha/lib/extra.sh" 'echo extra'
git -C "$case_dir/market" add -A
git -C "$case_dir/market" commit -q -m three
SHA3=$(git -C "$case_dir/market" rev-parse HEAD)
seed_cache_from "$case_dir" "$SHA3" >/dev/null
mkdir -p "$case_dir/present-repo"
write "$case_dir/installed_plugins.json" "{
  \"version\": 1,
  \"plugins\": {
    \"alpha@market1\": [
      {\"scope\":\"user\",\"version\":\"1.0.0\",\"gitCommitSha\":\"$SHA2\",\"installPath\":\"$case_dir/cache/alpha/1.0.0\"},
      {\"scope\":\"project\",\"version\":\"1.0.0\",\"gitCommitSha\":\"$SHA3\",\"installPath\":\"$case_dir/cache/alpha/1.0.0\",\"projectPath\":\"$case_dir/present-repo\"}
    ]
  }
}"
write "$case_dir/known_marketplaces.json" \
  "{\"market1\": {\"installLocation\": \"$case_dir/market\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
out=$(run_check "$case_dir" --marketplace market1 --scope all)
rc=$?
assert_exit "shared source dir, two shas: exit 0" 0 "$rc"
assert_eq "shared source dir: both records checked" "2" "$(jq -r '.checked' <<<"$out" 2>/dev/null)"
assert_eq "shared source dir: the record at the newer sha matches" "match" \
  "$(jq -r --arg s "$SHA3" 'first(.installs[] | select(.gitCommitSha == $s) | .verdict)' <<<"$out" 2>/dev/null)"
assert_eq "shared source dir: the record at the older sha is not-at-head, though the clone holds it" "not-at-head" \
  "$(jq -r --arg s "$SHA2" 'first(.installs[] | select(.gitCommitSha == $s) | .verdict)' <<<"$out" 2>/dev/null)"
assert_eq "shared source dir: no file is reported against the older record" "0 0 0" \
  "$(jq -r --arg s "$SHA2" 'first(.installs[] | select(.gitCommitSha == $s) | "\(.differing) \(.missing_from_cache) \(.extra_in_cache)")' <<<"$out" 2>/dev/null)"
assert_eq "shared source dir: 1 match, 1 not checked, nothing stale" "1 1 0" \
  "$(jq -r '"\(.match) \(.not_checked) \(.stale_content)"' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
repo="$case_dir/market"
init_fixture_repo "$repo"
write "$repo/.claude-plugin/marketplace.json" \
  '{"plugins":[{"name":"alpha","source":"./plugins/alpha"},{"name":"nested","source":"./plugins/alpha/nested"}]}'
write "$repo/plugins/alpha/root.sh" 'echo root'
write "$repo/plugins/alpha/nested/inner.sh" 'echo inner'
git -C "$repo" add -A
git -C "$repo" commit -q -m nested-sources
NESTED_SHA=$(git -C "$repo" rev-parse HEAD)
mkdir -p "$case_dir/cache/alpha/1.0.0/nested" "$case_dir/cache/nested/1.0.0"
write "$case_dir/cache/alpha/1.0.0/root.sh" 'echo root'
write "$case_dir/cache/alpha/1.0.0/nested/inner.sh" 'echo inner'
write "$case_dir/cache/nested/1.0.0/inner.sh" 'echo inner'
write "$case_dir/installed_plugins.json" "{
  \"version\": 1,
  \"plugins\": {
    \"alpha@market1\": [
      {\"scope\":\"user\",\"version\":\"1.0.0\",\"gitCommitSha\":\"$NESTED_SHA\",\"installPath\":\"$case_dir/cache/alpha/1.0.0\"}
    ],
    \"nested@market1\": [
      {\"scope\":\"user\",\"version\":\"1.0.0\",\"gitCommitSha\":\"$NESTED_SHA\",\"installPath\":\"$case_dir/cache/nested/1.0.0\"}
    ]
  }
}"
write "$case_dir/known_marketplaces.json" \
  "{\"market1\": {\"installLocation\": \"$case_dir/market\", \"lastUpdated\": \"2026-01-01T00:00:00Z\"}}"
out=$(run_check "$case_dir" --marketplace market1)
rc=$?
assert_exit "nested sources: exit 0" 0 "$rc"
assert_eq "nested sources: both records checked" "2" "$(jq -r '.checked' <<<"$out" 2>/dev/null)"
assert_eq "nested sources: the ancestor cache that holds the nested subtree is a match" \
  "match" "$(jq -r 'first(.installs[] | select(.id == "alpha@market1") | .verdict)' <<<"$out" 2>/dev/null)"
assert_eq "nested sources: the nested plugin is a match" \
  "match" "$(jq -r 'first(.installs[] | select(.id == "nested@market1") | .verdict)' <<<"$out" 2>/dev/null)"
assert_eq "nested sources: neither is stale" "0" "$(jq -r '.stale_content' <<<"$out" 2>/dev/null)"
rm -f "$case_dir/cache/alpha/1.0.0/nested/inner.sh"
out=$(run_check "$case_dir" --marketplace market1)
assert_eq "nested sources: an ancestor cache missing the nested file is stale-content" \
  "stale-content" "$(jq -r 'first(.installs[] | select(.id == "alpha@market1") | .verdict)' <<<"$out" 2>/dev/null)"
assert_eq "nested sources: that hole is missing-from-cache, not a cache-only extra" \
  "1 0" "$(jq -r 'first(.installs[] | select(.id == "alpha@market1") | "\(.missing_from_cache) \(.extra_in_cache)")' <<<"$out" 2>/dev/null)"
assert_eq "nested sources: the nested plugin is unaffected" \
  "match" "$(jq -r 'first(.installs[] | select(.id == "nested@market1") | .verdict)' <<<"$out" 2>/dev/null)"

count_creations() {
  local trace="$1" forks execs
  forks=$(grep -oE '^\++[0-9]+\+' "$trace" | sort -u | wc -l | tr -d ' ')
  execs=$(grep -cE '^\++[0-9]+\+ (command )?(jq|git|find|tr|realpath|readlink|mktemp|head|sed|cat|grep|awk|sort|uniq|cut|wc|date|dirname|basename|ls) ' "$trace" || true)
  echo $((forks - 1 + execs))
}

seed_budget_case() {
  local case_dir="$1" n="$2" repo="$1/market" i
  init_fixture_repo "$repo"
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
  write "$case_dir/ps4.env" 'PS4='\''+${BASHPID}+ '\'''
  env \
    CACHE_CONTENT_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    CACHE_CONTENT_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    BASH_ENV="$case_dir/ps4.env" \
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
if [[ "$large" -ge 1 ]]; then
  pass "process budget: the trace probe actually counted something (measured $large)"
else
  fail "process budget: the trace probe actually counted something" \
    "measured $large — the pid-stamped PS4 did not reach the traced shell, so the ceiling below is vacuous (trace: $case_dir/trace-large.log)"
fi
if [[ "$large" -ge 1 && "$large" -le 26 ]]; then
  pass "process budget: a one-install report costs at most 26 process creations (measured $large)"
else
  fail "process budget: a one-install report costs at most 26 process creations" \
    "measured $large (trace: $case_dir/trace-large.log)"
fi

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] && exit 0
exit 1
