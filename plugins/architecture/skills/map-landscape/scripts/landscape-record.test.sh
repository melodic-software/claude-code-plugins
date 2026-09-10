#!/usr/bin/env bash
# Self-contained tests for landscape-record.sh (skill-script shape, per
# docs/conventions/shell-test-helpers/README.md: per-plugin assertion
# primitives are duplicated on purpose, never shared across plugins).
#
# Every fixture is built in a mktemp directory and torn down on exit; nothing
# here reads or writes a real repository.
set -uo pipefail

# Isolate the fixture repositories from any ambient git environment: `git -C`
# changes directory but does not override discovery, so an exported GIT_DIR
# would land these throwaway identities in the CALLER's .git/config.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/landscape-record.sh"
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
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3
  actual: $2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3
  actual: $2" ;;
  *) pass "$1" ;;
  esac
}
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}

make_repo() {
  local dir="$TEST_TMPDIR/$1"
  mkdir -p "$dir"
  git -C "$dir" init --quiet 2>/dev/null
  git -C "$dir" config user.email "fixture@example.invalid"
  git -C "$dir" config user.name "Fixture"
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config core.autocrlf false
  git -C "$dir" remote add origin "https://github.com/fixture-owner/$1.git"
  printf '%s' "$dir"
}

commit_repo() {
  git -C "$1" add -A 2>/dev/null
  git -C "$1" commit --quiet --no-verify -m "fixture" 2>/dev/null
}

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed" >&2
  exit 0
fi

# --- The fixture repository -------------------------------------------------
repo="$(make_repo hub)"
mkdir -p "$repo/.github/workflows" "$repo/docs"
cat >"$repo/.github/workflows/ci.yml" <<'YML'
jobs:
  build:
    uses: fixture-owner/ci-workflows/.github/workflows/build.yml@v2
YML
cat >"$repo/docs/notes.md" <<'MD'
Conventions live in fixture-owner/standards.
MD
printf 'echo hi\n' >"$repo/run.sh"
commit_repo "$repo"

# --- Case group 1: the record's shape ---------------------------------------
out="$(bash "$SCRIPT" "$repo")"
rc=$?
assert_equals "record: a clean build exits 0" "$rc" "0"
assert_contains "record: it declares schema_version 1" "$out" '"schema_version": 1'
assert_contains "record: it carries a generated-on date" "$out" '"generated_on": "'
assert_contains "record: the discovery source defaults to the explicit list" "$out" '"discovery_source": "explicit list"'
assert_contains "record: remote is off unless asked for" "$out" '"remote": "not used"'
assert_contains "record: the repository's facts are embedded whole" "$out" '{"name":"hub",'
assert_not_contains "record: minus the local checkout path, which is not architecture" "$out" '"path":'
assert_contains "record: so are the edges" "$out" '"to":"fixture-owner/ci-workflows"'
assert_contains "record: including the weaker cites edge" "$out" '"to":"fixture-owner/standards"'

# One object per line keeps the record diffable and parseable without a JSON
# library, so the shape itself is asserted rather than left to chance.
obj_lines="$(printf '%s\n' "$out" | grep -c '^    {')"
assert_equals "record: every array element sits on its own line" "$obj_lines" "4"

if command -v node >/dev/null 2>&1; then
  printf '%s\n' "$out" >"$TEST_TMPDIR/parse.json"
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$TEST_TMPDIR/parse.json" 2>/dev/null
  assert_equals "record: it parses as JSON" "$?" "0"
else
  pass "record: JSON parse skipped, node not installed"
fi

# --- Case group 2: the recorded provenance is what the caller said ----------
out="$(bash "$SCRIPT" "$repo" --source "current repository plus reference graph" --remote "used, owned only")"
assert_contains "provenance: --source is recorded verbatim" "$out" '"discovery_source": "current repository plus reference graph"'
assert_contains "provenance: --remote is recorded verbatim" "$out" '"remote": "used, owned only"'
out="$(bash "$SCRIPT" "$repo" --source=inline --remote=inline)"
assert_contains "provenance: the = spelling works too" "$out" '"discovery_source": "inline"'

# --- Case group 3: a repository with nothing to relate ----------------------
quiet="$(make_repo quiet)"
printf 'Nothing references anything here.\n' >"$quiet/README.md"
commit_repo "$quiet"
out="$(bash "$SCRIPT" "$quiet")"
assert_contains "empty: an edgeless repository still records its facts" "$out" '{"name":"quiet",'
assert_contains "empty: and an empty edge array, not a missing key" "$out" '"edges": []'

# --- Case group 4: --edges-from picks the citing repository -----------------
out="$(bash "$SCRIPT" "$quiet" "$repo" --edges-from "$repo")"
assert_contains "edges-from: facts cover both repositories" "$out" '{"name":"quiet",'
assert_contains "edges-from: and edges come from the named one" "$out" '"from":"hub"'
out="$(bash "$SCRIPT" "$quiet" "$repo")"
assert_contains "edges-from: it defaults to the first path" "$out" '"edges": []'

# --- Case group 5: --owner reaches the edge extractor -----------------------
out="$(bash "$SCRIPT" "$repo" --owner other-org)"
assert_contains "owner: an override marks a same-name target external" "$out" '"relation":"external"'
assert_not_contains "owner: and no longer trusts the old owner's bare tokens" "$out" '"to":"fixture-owner/standards"'

# --- Case group 6: drift against an identical record ------------------------
bash "$SCRIPT" "$repo" >"$TEST_TMPDIR/committed.json"
out="$(bash "$SCRIPT" "$repo" --drift-against "$TEST_TMPDIR/committed.json")"
rc=$?
assert_equals "drift: an unchanged repository exits 0" "$rc" "0"
assert_contains "drift: and says so plainly" "$out" "none"

# --- Case group 7: drift the caller must see --------------------------------
sed 's|"fixture-owner/ci-workflows"|"fixture-owner/gone-away"|' \
  "$TEST_TMPDIR/committed.json" >"$TEST_TMPDIR/edge-drift.json"
out="$(bash "$SCRIPT" "$repo" --drift-against "$TEST_TMPDIR/edge-drift.json")"
rc=$?
assert_equals "drift: a changed edge exits 3, the check-failure code" "$rc" "3"
assert_contains "drift: the vanished edge is named" "$out" "removed edge: fixture-owner/gone-away"
assert_contains "drift: so is the new one" "$out" "added edge: fixture-owner/ci-workflows"

sed 's|"runtime":"shell"|"runtime":"rust"|' \
  "$TEST_TMPDIR/committed.json" >"$TEST_TMPDIR/fact-drift.json"
out="$(bash "$SCRIPT" "$repo" --drift-against "$TEST_TMPDIR/fact-drift.json")"
assert_equals "drift: a changed fact exits 3 too" "$?" "3"
assert_contains "drift: it names the field, the old value and the new" "$out" 'changed fact on hub: runtime: "rust" -> "shell"'

# A record written by an earlier version still carries `path`; comparing against
# one must not report the local checkout location as architecture drift.
sed 's|{"name":"hub",|{"name":"hub","path":"/somewhere/else",|' \
  "$TEST_TMPDIR/committed.json" >"$TEST_TMPDIR/path-drift.json"
out="$(bash "$SCRIPT" "$repo" --drift-against "$TEST_TMPDIR/path-drift.json")"
assert_equals "drift: a moved checkout is not architecture drift" "$?" "0"

# A repository anyone is working in moves its HEAD constantly, so the timestamp
# is reported and never gated on: a check lane red on every commit gets muted.
sed 's|"last_touched":"[^"]*"|"last_touched":"2020-01-01T00:00:00+00:00"|' \
  "$TEST_TMPDIR/committed.json" >"$TEST_TMPDIR/time-drift.json"
out="$(bash "$SCRIPT" "$repo" --drift-against "$TEST_TMPDIR/time-drift.json")"
assert_equals "drift: a newer HEAD does not fail the check" "$?" "0"
assert_contains "drift: but it is still reported" "$out" "moved on hub: last_touched"

# A repository that left the record, and one that joined it.
out="$(bash "$SCRIPT" "$repo" "$quiet" --edges-from "$repo" \
  --drift-against "$TEST_TMPDIR/committed.json")"
assert_equals "drift: a new repository exits 3" "$?" "3"
assert_contains "drift: and is named as added" "$out" "added repository: quiet"

bash "$SCRIPT" "$repo" "$quiet" --edges-from "$repo" >"$TEST_TMPDIR/two.json"
out="$(bash "$SCRIPT" "$repo" --drift-against "$TEST_TMPDIR/two.json")"
assert_contains "drift: a dropped repository is named as removed" "$out" "removed repository: quiet"

# --- Case group 8: evidence that no longer exists ---------------------------
rm "$repo/docs/notes.md"
commit_repo "$repo"
out="$(bash "$SCRIPT" "$repo" --drift-against "$TEST_TMPDIR/committed.json")"
assert_equals "evidence: a deleted citation is drift" "$?" "3"
assert_contains "evidence: the edge it supported is named as removed" "$out" "removed edge: fixture-owner/standards"

# A record whose cited file is gone while the edge survives: the report says so
# rather than leaving a dangling citation in a committed artifact.
ev_repo="$(make_repo evidence)"
mkdir -p "$ev_repo/docs"
printf 'We use fixture-owner/toolkit here.\n' >"$ev_repo/docs/a.md"
printf 'And fixture-owner/toolkit here too.\n' >"$ev_repo/docs/b.md"
commit_repo "$ev_repo"
bash "$SCRIPT" "$ev_repo" >"$TEST_TMPDIR/ev.json"
rm "$ev_repo/docs/b.md"
commit_repo "$ev_repo"
out="$(bash "$SCRIPT" "$ev_repo" --drift-against "$TEST_TMPDIR/ev.json")"
assert_not_contains "evidence: an edge still cited by one file survives" "$out" "removed edge: fixture-owner/toolkit"
assert_contains "evidence: but the count change is reported" "$out" "changed"

# --- Case group 9: a record this script will not compare against ------------
printf '{"schema_version": 2, "repositories": [], "edges": []}\n' >"$TEST_TMPDIR/v2.json"
bad="$(bash "$SCRIPT" "$repo" --drift-against "$TEST_TMPDIR/v2.json" 2>&1)"
assert_equals "schema: an unknown version exits 1" "$?" "1"
assert_contains "schema: and says which version it wanted" "$bad" "schema_version 1"

bad="$(bash "$SCRIPT" "$repo" --drift-against "$TEST_TMPDIR/absent.json" 2>&1)"
assert_equals "schema: an unreadable record exits 1" "$?" "1"

# --- Case group 10: usage ---------------------------------------------------
bash "$SCRIPT" >/dev/null 2>&1
assert_equals "usage: no repository path exits 2" "$?" "2"

bash "$SCRIPT" "$repo" --edges-from >/dev/null 2>&1
assert_equals "usage: --edges-from without a value exits 2" "$?" "2"

bash "$SCRIPT" "$repo" --nonsense >/dev/null 2>&1
assert_equals "usage: an unknown option exits 2" "$?" "2"

bash "$SCRIPT" "$repo" --edges-from "$TEST_TMPDIR/nowhere" >/dev/null 2>&1
assert_equals "usage: an --edges-from path that is not there exits 1" "$?" "1"

help_out="$(bash "$SCRIPT" --help 2>&1)"
assert_equals "usage: --help exits 0" "$?" "0"
assert_contains "usage: and describes the record" "$help_out" "schema_version"

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
exit 0
