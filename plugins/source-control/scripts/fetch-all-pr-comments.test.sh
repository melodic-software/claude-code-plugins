#!/usr/bin/env bash
# Regression tests for fetch-all-pr-comments.sh.
#
# Black-box: invokes the script as a subprocess with a stubbed `gh` on PATH.
# Covers:
#
#   1. All 3 surfaces appear in output (general, review, inline)
#   2. Output is sorted by created_at
#   3. Missing PR number — exits 1
#   4. gh api failure — exits 2
#   5. Output schema — every object has required fields
#   6. Empty PR (no comments) — exits 0 with empty array

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/fetch-all-pr-comments.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

# ---- Build fixtures ---------------------------------------------------------

# Surface 1: issue-level comments
FIXTURE_GENERAL="$TEST_TMPDIR/general.json"
cat >"$FIXTURE_GENERAL" <<'JSON'
[
  {
    "id": 1001,
    "user": {"login": "alice"},
    "body": "Looks good overall",
    "created_at": "2026-05-20T10:00:00Z"
  }
]
JSON

# Surface 2: reviews (one with body, one empty — empty should be filtered)
FIXTURE_REVIEWS="$TEST_TMPDIR/reviews.json"
cat >"$FIXTURE_REVIEWS" <<'JSON'
[
  {
    "id": 2001,
    "user": {"login": "bob"},
    "body": "Request changes on auth flow",
    "submitted_at": "2026-05-20T11:00:00Z"
  },
  {
    "id": 2002,
    "user": {"login": "charlie"},
    "body": "",
    "submitted_at": "2026-05-20T11:30:00Z"
  }
]
JSON

# Surface 3: inline review comments
FIXTURE_INLINE="$TEST_TMPDIR/inline.json"
cat >"$FIXTURE_INLINE" <<'JSON'
[
  {
    "id": 3001,
    "user": {"login": "codex[bot]"},
    "body": "Missing null check here",
    "path": "src/Auth.cs",
    "line": 42,
    "original_line": null,
    "created_at": "2026-05-20T09:30:00Z"
  },
  {
    "id": 3002,
    "user": {"login": "codex[bot]"},
    "body": "Stale count reference",
    "path": "src/Counter.cs",
    "line": null,
    "original_line": 15,
    "created_at": "2026-05-20T12:00:00Z"
  }
]
JSON

# ---- Build gh stub ----------------------------------------------------------

PR_NUM=42

GH_STUB="$TEST_TMPDIR/bin/gh"
mkdir -p "$TEST_TMPDIR/bin"
cat >"$GH_STUB" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"repo view"*owner*)
    printf 'testowner'
    ;;
  *"repo view"*name*)
    printf 'testrepo'
    ;;
  *issues/${PR_NUM}/comments*)
    cat "$FIXTURE_GENERAL"
    ;;
  *pulls/${PR_NUM}/reviews*)
    cat "$FIXTURE_REVIEWS"
    ;;
  *pulls/${PR_NUM}/comments*)
    cat "$FIXTURE_INLINE"
    ;;
  *)
    printf 'gh stub: unhandled: %s\n' "\$*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$GH_STUB"

# ---- Tests ------------------------------------------------------------------

# Case 1: missing PR number — capture exit code via subshell
rc=$(
  PATH="$TEST_TMPDIR/bin:$PATH" bash "$SCRIPT" 2>/dev/null
  echo $?
)
assert_eq "missing PR number exits 1" "1" "$rc"

# Case 2: all 3 surfaces in output
out=$(PATH="$TEST_TMPDIR/bin:$PATH" bash "$SCRIPT" "$PR_NUM" 2>/dev/null)
rc=$?
assert_eq "success exit 0" "0" "$rc"

type_count=$(printf '%s' "$out" | jq '[.[] | .type] | unique | length')
assert_eq "3 surface types present" "3" "$type_count"

has_general=$(printf '%s' "$out" | jq '[.[] | select(.type == "general")] | length')
assert_eq "general comments present" "1" "$has_general"

has_review=$(printf '%s' "$out" | jq '[.[] | select(.type == "review")] | length')
assert_eq "review comments present (empty filtered)" "1" "$has_review"

has_inline=$(printf '%s' "$out" | jq '[.[] | select(.type == "inline")] | length')
assert_eq "inline comments present" "2" "$has_inline"

# Case 3: sorted by created_at (earliest first)
first_created=$(printf '%s' "$out" | jq -r '.[0].created_at')
last_created=$(printf '%s' "$out" | jq -r '.[-1].created_at')
assert_eq "first is earliest" "2026-05-20T09:30:00Z" "$first_created"
assert_eq "last is latest" "2026-05-20T12:00:00Z" "$last_created"

# Case 4: schema check — all objects have required fields
missing_fields=$(printf '%s' "$out" | jq '[.[] | select(.id == null or .type == null or .author == null or .body == null or .created_at == null)] | length')
assert_eq "all objects have required fields" "0" "$missing_fields"

# Case 5: inline comments carry path and line
inline_with_path=$(printf '%s' "$out" | jq '[.[] | select(.type == "inline" and .path != null)] | length')
assert_eq "inline comments have path" "2" "$inline_with_path"

# Case 6: fallback to original_line when line is null
fallback_line=$(printf '%s' "$out" | jq '[.[] | select(.id == 3002)] | .[0].line')
assert_eq "original_line fallback" "15" "$fallback_line"

# Case 7: gh api failure exits 2
FAIL_STUB="$TEST_TMPDIR/bin-fail/gh"
mkdir -p "$TEST_TMPDIR/bin-fail"
cat >"$FAIL_STUB" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*"owner"*) printf 'testowner' ;;
  *"repo view"*"name"*) printf 'testrepo' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$FAIL_STUB"

rc=$(
  PATH="$TEST_TMPDIR/bin-fail:$PATH" bash "$SCRIPT" "$PR_NUM" 2>/dev/null
  echo $?
)
assert_eq "gh api failure exits 2" "2" "$rc"

# Case 8: empty PR (no comments on any surface)
EMPTY_STUB="$TEST_TMPDIR/bin-empty/gh"
mkdir -p "$TEST_TMPDIR/bin-empty"
cat >"$EMPTY_STUB" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*"owner"*) printf 'testowner' ;;
  *"repo view"*"name"*) printf 'testrepo' ;;
  *) printf '[]' ;;
esac
STUB
chmod +x "$EMPTY_STUB"

out=$(PATH="$TEST_TMPDIR/bin-empty:$PATH" bash "$SCRIPT" "$PR_NUM" 2>/dev/null)
rc=$?
assert_eq "empty PR exits 0" "0" "$rc"
empty_count=$(printf '%s' "$out" | jq 'length')
assert_eq "empty PR returns empty array" "0" "$empty_count"

# ---- Summary ----------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
