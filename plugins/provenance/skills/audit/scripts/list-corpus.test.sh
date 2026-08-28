#!/usr/bin/env bash
# Self-contained tests for list-corpus.sh. Fixtures are built inline in a
# tmpdir, so no corpus sample sits in the tree. Per the shell-test-helpers
# convention, the assertion helpers are local to this suite rather than shared
# across plugins.
#
# The load-bearing case here is "fixture tree is included without config"
# (the #3041 resolution): an unconditional exclusion inside the script would
# blind the eval harness to its own fixtures, so the exclusion has to arrive
# through the config layer and this suite proves the script ships without it.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# make the fixture repo operate on the CALLER's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST_CORPUS="$SCRIPT_DIR/list-corpus.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed (this suite reads the script's JSON product)" >&2
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed (the corpus is the tracked-file set)" >&2
  exit 0
fi

# Fixture CONFIG isolation, the same idea as the git isolation above:
# list-corpus.sh resolves its cascade from $HOME and CLAUDE_PROJECT_DIR, so
# running this suite inside a repo that ships `.claude/provenance.json` would
# grade the fixtures against THAT repo's exclusions. Cases that exercise the
# cascade set CLAUDE_PROJECT_DIR per invocation and override this.
export HOME="$TEST_TMPDIR/home"
mkdir -p "$HOME"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $3" "exit $2"; fi
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
  esac
}

# --- Fixture repository ----------------------------------------------------------

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO"/{docs/topics,plugins/demo/skills/audit/vendor,legacy}
mkdir -p "$REPO/plugins/demo/skills/audit/evals/fixtures/golden/case-1"

write_file() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
}

write_file "$REPO/README.md" "# Demo repo"
write_file "$REPO/docs/guide.md" "# Guide"
write_file "$REPO/docs/topics/notes.md" "# Notes"
write_file "$REPO/docs/plain.txt" "not markdown"
write_file "$REPO/plugins/demo/skills/audit/vendor/upstream.md" "# Vendored upstream page"
write_file "$REPO/plugins/demo/skills/audit/evals/fixtures/golden/case-1/case.md" "# Planted copy"
write_file "$REPO/legacy/old.md" "# Legacy"

git -C "$REPO" init -q
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "fixture corpus"

# Untracked markdown must never enter the corpus.
write_file "$REPO/docs/untracked.md" "# Untracked"

# A second repo whose gitattributes marks a tree linguist-vendored.
ATTR_REPO="$TEST_TMPDIR/attr-repo"
mkdir -p "$ATTR_REPO/third-party"
write_file "$ATTR_REPO/.gitattributes" "third-party/** linguist-vendored"
write_file "$ATTR_REPO/kept.md" "# Kept"
write_file "$ATTR_REPO/third-party/copied.md" "# Copied upstream"
git -C "$ATTR_REPO" init -q
git -C "$ATTR_REPO" config user.email "test@example.com"
git -C "$ATTR_REPO" config user.name "Test"
git -C "$ATTR_REPO" add -A
git -C "$ATTR_REPO" commit -qm "attr fixture"

CFG_DIR="$REPO/.claude"
mkdir -p "$CFG_DIR"

run_default() {
  # A run with no config layers: CLAUDE_PROJECT_DIR points at a config-free
  # directory so the fixture repo's own .claude/ never leaks into the case.
  local noconfig="$TEST_TMPDIR/noconfig"
  mkdir -p "$noconfig"
  (cd "$REPO" && CLAUDE_PROJECT_DIR="$noconfig" bash "$LIST_CORPUS" "$@")
}

# --- Usage and argument handling -------------------------------------------------

OUT="$(bash "$LIST_CORPUS" --help 2>&1)"
assert_exit "--help exits 0" "$?" "0"
assert_contains "--help names the script" "$OUT" "list-corpus.sh"

OUT="$(bash "$LIST_CORPUS" --nope 2>&1)"
assert_exit "unknown argument exits 2" "$?" "2"

OUT="$(run_default 2>/dev/null)"
assert_exit "clean run exits 0" "$?" "0"

echo "$OUT" | jq -e . >/dev/null 2>&1
assert_exit "stdout is valid JSON" "$?" "0"

# --- Corpus membership -----------------------------------------------------------

FILES="$(echo "$OUT" | jq -r '.files[]')"
assert_contains "tracked markdown at the root is listed" "$FILES" "README.md"
assert_contains "tracked markdown in a subdirectory is listed" "$FILES" "docs/guide.md"
assert_contains "tracked markdown nested deeper is listed" "$FILES" "docs/topics/notes.md"
assert_not_contains "untracked markdown is not listed" "$FILES" "docs/untracked.md"
assert_not_contains "tracked non-markdown is not listed" "$FILES" "docs/plain.txt"

assert_eq "paths are repo-relative" \
  "$(echo "$OUT" | jq -r '[.files[] | select(startswith("/"))] | length')" "0"

# --- Built-in categorical carve-outs ---------------------------------------------

assert_not_contains "a vendored tree is not listed" "$FILES" "vendor/upstream.md"
assert_eq "the vendored file is declined once" \
  "$(echo "$OUT" | jq -r '[.declined[] | select(.path_pattern | test("vendor")) | .count] | add')" "1"
assert_contains "the vendor decline states a reason" \
  "$(echo "$OUT" | jq -r '.declined[] | select(.path_pattern | test("vendor")) | .reason')" "vendored"

ATTR_OUT="$(cd "$ATTR_REPO" && CLAUDE_PROJECT_DIR="$TEST_TMPDIR/noconfig" bash "$LIST_CORPUS" 2>/dev/null)"
assert_contains "a non-vendored file in the attr repo is listed" \
  "$(echo "$ATTR_OUT" | jq -r '.files[]')" "kept.md"
assert_not_contains "a linguist-vendored path is not listed" \
  "$(echo "$ATTR_OUT" | jq -r '.files[]')" "third-party/copied.md"
assert_contains "the linguist-vendored decline names the attribute" \
  "$(echo "$ATTR_OUT" | jq -r '.declined[].reason')" "linguist-vendored"

# The #3041 invariant. The eval-fixture tree is excluded through config, never
# unconditionally, so a run with no config layers MUST see the fixtures.
assert_contains "the eval-fixture tree is included when no config excludes it" \
  "$FILES" "evals/fixtures/golden/case-1/case.md"

# --- Counts ----------------------------------------------------------------------

assert_eq "considered equals included plus declined" \
  "$(echo "$OUT" | jq -r '.counts.considered == (.counts.included + .counts.declined)')" "true"
assert_eq "included matches the files array length" \
  "$(echo "$OUT" | jq -r '.counts.included == (.files | length)')" "true"
assert_eq "declined matches the declined counts" \
  "$(echo "$OUT" | jq -r '.counts.declined == ([.declined[].count] | add // 0)')" "true"

# --- Config cascade --------------------------------------------------------------

printf '%s\n' '{"excluded_paths":["legacy/**"]}' >"$CFG_DIR/provenance.json"
TEAM_OUT="$(cd "$REPO" && CLAUDE_PROJECT_DIR="$REPO" bash "$LIST_CORPUS" 2>/dev/null)"
assert_not_contains "a team-config exclusion drops the path" \
  "$(echo "$TEAM_OUT" | jq -r '.files[]')" "legacy/old.md"
assert_contains "the config decline names the config layer" \
  "$(echo "$TEAM_OUT" | jq -r '.declined[] | select(.path_pattern == "legacy/**") | .reason')" "excluded_paths"
assert_eq "the config decline carries its own pattern" \
  "$(echo "$TEAM_OUT" | jq -r '.declined[] | select(.path_pattern == "legacy/**") | .count')" "1"

printf '%s\n' '{"excluded_paths":["**/evals/fixtures/golden/**"]}' >"$CFG_DIR/provenance.json"
FIX_OUT="$(cd "$REPO" && CLAUDE_PROJECT_DIR="$REPO" bash "$LIST_CORPUS" 2>/dev/null)"
assert_not_contains "the fixture tree declines under a config entry" \
  "$(echo "$FIX_OUT" | jq -r '.files[]')" "evals/fixtures/golden/case-1/case.md"
assert_contains "legacy returns once the config no longer excludes it" \
  "$(echo "$FIX_OUT" | jq -r '.files[]')" "legacy/old.md"

printf '%s\n' '{"excluded_paths":["docs/**"]}' >"$CFG_DIR/provenance.local.json"
OVERLAY_OUT="$(cd "$REPO" && CLAUDE_PROJECT_DIR="$REPO" bash "$LIST_CORPUS" 2>/dev/null)"
assert_not_contains "the local overlay's exclusion applies" \
  "$(echo "$OVERLAY_OUT" | jq -r '.files[]')" "docs/guide.md"
assert_contains "the overlay replaces the team value per key" \
  "$(echo "$OVERLAY_OUT" | jq -r '.files[]')" "evals/fixtures/golden/case-1/case.md"
# Per-key override means a later layer REPLACES the value, and an explicit empty
# array is a value. Treating "no elements" as "key absent" left the team layer's
# exclusions in force, so an overlay could add exclusions but never clear them.
printf '%s\n' '{"excluded_paths":["docs/**"]}' >"$CFG_DIR/provenance.json"
printf '%s\n' '{"excluded_paths":[]}' >"$CFG_DIR/provenance.local.json"
CLEAR_OUT="$(cd "$REPO" && CLAUDE_PROJECT_DIR="$REPO" bash "$LIST_CORPUS" 2>/dev/null)"
assert_contains "an explicit empty overlay clears an inherited exclusion" \
  "$(echo "$CLEAR_OUT" | jq -r '.files[]')" "docs/guide.md"
assert_eq "clearing leaves only the built-in carve-outs declined" \
  "$(echo "$CLEAR_OUT" | jq -r '[.declined[] | select(.reason | test("excluded_paths"))] | length')" "0"
rm -f "$CFG_DIR/provenance.local.json" "$CFG_DIR/provenance.json"

mkdir -p "$HOME/.claude"
printf '%s\n' '{"excluded_paths":["README.md"]}' >"$HOME/.claude/provenance.json"
USER_OUT="$(cd "$REPO" && CLAUDE_PROJECT_DIR="$TEST_TMPDIR/noconfig" bash "$LIST_CORPUS" 2>/dev/null)"
assert_not_contains "the user-global layer is read" \
  "$(echo "$USER_OUT" | jq -r '.files[]')" "README.md"
rm -f "$HOME/.claude/provenance.json"

# --- --show-config ---------------------------------------------------------------

OUT_SC="$(run_default --show-config 2>&1)"
assert_exit "--show-config exits 0" "$?" "0"
assert_contains "--show-config reports no layers when none exist" "$OUT_SC" "bundled defaults"

printf '%s\n' '{"excluded_paths":["legacy/**"]}' >"$CFG_DIR/provenance.json"
OUT_SC="$(cd "$REPO" && CLAUDE_PROJECT_DIR="$REPO" bash "$LIST_CORPUS" --show-config 2>&1)"
assert_contains "--show-config names the team layer" "$OUT_SC" "$CFG_DIR/provenance.json"
assert_contains "--show-config prints the effective exclusions" "$OUT_SC" "legacy/**"
rm -f "$CFG_DIR/provenance.json"

# --- Targets ---------------------------------------------------------------------

DIR_OUT="$(run_default docs 2>/dev/null)"
DIR_FILES="$(echo "$DIR_OUT" | jq -r '.files[]')"
assert_contains "a directory target lists its markdown" "$DIR_FILES" "docs/guide.md"
assert_not_contains "a directory target excludes siblings" "$DIR_FILES" "README.md"

FILE_OUT="$(run_default docs/guide.md 2>/dev/null)"
assert_eq "a file target lists exactly that file" \
  "$(echo "$FILE_OUT" | jq -r '.files | length')" "1"
assert_eq "a file target names the file" \
  "$(echo "$FILE_OUT" | jq -r '.files[0]')" "docs/guide.md"

run_default no/such/path >/dev/null 2>&1
assert_exit "a nonexistent target exits 2" "$?" "2"

# The repository root has several spellings and every one of them means "the
# whole corpus". `.` reaching the directory-prefix filter as a literal prefix
# matched nothing and reported an empty corpus with no error, which reads as a
# clean repository rather than as a broken invocation.
BASE_FILES="$(run_default 2>/dev/null | jq -r '.counts.included')"
assert_eq "a '.' target scans the whole repository" \
  "$(run_default . 2>/dev/null | jq -r '.counts.included')" "$BASE_FILES"
assert_eq "a './' target scans the whole repository" \
  "$(run_default ./ 2>/dev/null | jq -r '.counts.included')" "$BASE_FILES"
assert_eq "an absolute repo-root target scans the whole repository" \
  "$(run_default "$REPO" 2>/dev/null | jq -r '.counts.included')" "$BASE_FILES"

# --- --paths-file ----------------------------------------------------------------

PATHS="$TEST_TMPDIR/paths.txt"
printf '%s\n' "docs/guide.md" "docs/topics/notes.md" >"$PATHS"
PF_OUT="$(run_default --paths-file "$PATHS" 2>/dev/null)"
assert_eq "--paths-file lists exactly its entries" \
  "$(echo "$PF_OUT" | jq -r '.files | length')" "2"
assert_contains "--paths-file keeps the listed file" \
  "$(echo "$PF_OUT" | jq -r '.files[]')" "docs/topics/notes.md"

printf '%s\n' "plugins/demo/skills/audit/vendor/upstream.md" >"$PATHS"
PF_OUT="$(run_default --paths-file "$PATHS" 2>/dev/null)"
assert_eq "--paths-file still applies the carve-outs" \
  "$(echo "$PF_OUT" | jq -r '.files | length')" "0"
assert_eq "the carved-out entry is declined, not dropped" \
  "$(echo "$PF_OUT" | jq -r '.counts.declined')" "1"

printf '%s\n' "docs/plain.txt" >"$PATHS"
PF_OUT="$(run_default --paths-file "$PATHS" 2>/dev/null)"
assert_contains "a non-markdown entry declines with a reason" \
  "$(echo "$PF_OUT" | jq -r '.declined[].reason')" "not markdown"

printf '%s\n' "docs/missing.md" >"$PATHS"
PF_OUT="$(run_default --paths-file "$PATHS" 2>/dev/null)"
assert_contains "a missing entry declines with a reason" \
  "$(echo "$PF_OUT" | jq -r '.declined[].reason')" "does not exist"

run_default --paths-file "$TEST_TMPDIR/absent.txt" >/dev/null 2>&1
assert_exit "an unreadable --paths-file exits 2" "$?" "2"

# --- Determinism -----------------------------------------------------------------

RUN_A="$(run_default 2>/dev/null)"
RUN_B="$(run_default 2>/dev/null)"
assert_eq "repeat runs produce identical output" "$RUN_A" "$RUN_B"

# --- Report ----------------------------------------------------------------------

printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
