#!/usr/bin/env bash
# Regression tests for fetch-annotations.sh.
#
# Black-box: invokes the script as a subprocess with a stubbed `gh` on PATH.
# Covers:
#
#   1. PR with mixed-conclusion check-runs — emits annotations for all
#   2. --failed flag — filters to only failure/timed_out/cancelled/action_required
#   3. PR with no check-runs — exits 0 with no output
#   4. Missing PR number — exits 1
#   5. gh pr view failure — exits 2
#   6. JSONL output schema — every line is valid JSON with required fields

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/fetch-annotations.sh"
# POSIX path for stub PATH entries (Git Bash PATH lookup fails on Windows-form
# paths like C:/Users/...). Production script accepts either form via env vars.
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/test-helpers.sh"

# Skip suite if jq missing — script depends on it.
command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

# ---- Build fixtures ---------------------------------------------------------

# check-runs response — three runs with different conclusions
FIXTURE_CHECK_RUNS="$TEST_TMPDIR/check-runs.json"
cat >"$FIXTURE_CHECK_RUNS" <<'JSON'
{
  "total_count": 3,
  "check_runs": [
    {"id": 100, "name": "build", "conclusion": "success", "status": "completed"},
    {"id": 200, "name": "test", "conclusion": "failure", "status": "completed"},
    {"id": 300, "name": "lint", "conclusion": "neutral", "status": "completed"}
  ]
}
JSON

# Annotations per check-run id
FIXTURE_ANNOT_100="$TEST_TMPDIR/annot-100.json"
echo '[]' >"$FIXTURE_ANNOT_100"

FIXTURE_ANNOT_200="$TEST_TMPDIR/annot-200.json"
cat >"$FIXTURE_ANNOT_200" <<'JSON'
[
  {
    "path": "src/Foo.cs",
    "start_line": 42,
    "end_line": 42,
    "annotation_level": "failure",
    "title": "CS0246",
    "message": "type or namespace 'Bar' could not be found"
  },
  {
    "path": "src/Foo.cs",
    "start_line": 99,
    "end_line": 100,
    "annotation_level": "warning",
    "title": "CS0168",
    "message": "variable declared but never used"
  }
]
JSON

FIXTURE_ANNOT_300="$TEST_TMPDIR/annot-300.json"
cat >"$FIXTURE_ANNOT_300" <<'JSON'
[
  {
    "path": "README.md",
    "start_line": 10,
    "end_line": 10,
    "annotation_level": "notice",
    "title": "MD013",
    "message": "Line length exceeds 80 chars"
  }
]
JSON

# check-runs response with a single failure-conclusion run whose id (999)
# the annotations stub treats as a simulated 403/rate-limit (Case 8).
FIXTURE_ANNOTFAIL_CHECK_RUNS="$TEST_TMPDIR/check-runs-annotfail.json"
cat >"$FIXTURE_ANNOTFAIL_CHECK_RUNS" <<'JSON'
{
  "total_count": 1,
  "check_runs": [
    {"id": 999, "name": "rate-limited-check", "conclusion": "failure", "status": "completed"}
  ]
}
JSON

# Empty check-runs response (Case 3)
FIXTURE_EMPTY_CHECK_RUNS="$TEST_TMPDIR/check-runs-empty.json"
cat >"$FIXTURE_EMPTY_CHECK_RUNS" <<'JSON'
{"total_count": 0, "check_runs": []}
JSON

# ---- Stub `gh` --------------------------------------------------------------
#
# Dispatch table:
#   pr view 1 --json headRefOid -q .headRefOid  → "abc1234"
#   pr view 2 --json headRefOid -q .headRefOid  → echo nothing, exit 1 (failure case)
#   pr view 3 --json headRefOid -q .headRefOid  → "empty5678"
#   api repos/.../commits/abc1234/check-runs    → fixture with 3 runs
#   api repos/.../commits/empty5678/check-runs  → fixture with 0 runs
#   api repos/.../check-runs/100/annotations    → []
#   api repos/.../check-runs/200/annotations    → 2 annotations
#   api repos/.../check-runs/300/annotations    → 1 annotation
#   repo view --json nameWithOwner ...          → example-org/example-repo

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
cat >"$STUB_DIR/gh" <<STUB_EOF
#!/usr/bin/env bash
set -uo pipefail
case "\$1" in
  pr)
    if [[ "\$2" == "view" ]]; then
      pr_num="\$3"
      case "\$pr_num" in
        1) echo "abc1234" ;;
        2) exit 1 ;;
        3) echo "empty5678" ;;
        4) echo "fail9999" ;;
        5) echo "annotfail99" ;;
        *) printf 'gh-stub: unknown pr number %q\n' "\$pr_num" >&2; exit 1 ;;
      esac
      exit 0
    fi
    ;;
  api)
    # Skip --paginate flag if present
    args=()
    for a in "\$@"; do
      [[ "\$a" == "--paginate" ]] && continue
      args+=("\$a")
    done
    set -- "\${args[@]}"
    case "\$2" in
      *commits/abc1234/check-runs*) cat "$FIXTURE_CHECK_RUNS"; exit 0 ;;
      *commits/empty5678/check-runs*) cat "$FIXTURE_EMPTY_CHECK_RUNS"; exit 0 ;;
      *commits/annotfail99/check-runs*) cat "$FIXTURE_ANNOTFAIL_CHECK_RUNS"; exit 0 ;;
      *check-runs/100/annotations*) cat "$FIXTURE_ANNOT_100"; exit 0 ;;
      *check-runs/200/annotations*) cat "$FIXTURE_ANNOT_200"; exit 0 ;;
      *check-runs/300/annotations*) cat "$FIXTURE_ANNOT_300"; exit 0 ;;
      *check-runs/999/annotations*) printf 'simulated 403 rate-limit\n' >&2; exit 1 ;;
      *) printf 'gh-stub: unknown api path %q\n' "\$2" >&2; exit 1 ;;
    esac
    ;;
  repo)
    if [[ "\$2" == "view" ]]; then
      echo "example-org/example-repo"
      exit 0
    fi
    ;;
  *) printf 'gh-stub: unknown command %q\n' "\$1" >&2; exit 1 ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh"

run_script() {
  PATH="$STUB_DIR:$PATH" \
    FETCH_ANNOT_REPO="example-org/example-repo" \
    bash "$SCRIPT" "$@" 2>&1
}

# Variant for cases that need to capture exit code without folding stderr.
# Output discarded; only exit code returned via $?.
run_script_silent() {
  PATH="$STUB_DIR:$PATH" \
    FETCH_ANNOT_REPO="example-org/example-repo" \
    bash "$SCRIPT" "$@" >/dev/null 2>&1
}

# ---- Cases ------------------------------------------------------------------

# Case 1: PR with mixed conclusions — emits annotations for all 3 check-runs
out=$(run_script 1)
# build (id=100) had no annotations; test (200) has 2; lint (300) has 1 → 3 total
line_count=$(printf '%s\n' "$out" | grep -c '^{' || true)
if [[ "$line_count" -eq 3 ]]; then
  pass "all-mode emits annotations from every check-run with non-empty list"
else
  fail "all-mode emits annotations from every check-run with non-empty list" "3 JSONL lines" "$line_count lines: $out"
fi

# Case 2: --failed filter — only failure-conclusion check-runs (test, id=200)
out=$(run_script 1 --failed)
line_count=$(printf '%s\n' "$out" | grep -c '^{' || true)
if [[ "$line_count" -eq 2 ]]; then
  pass "--failed filters to failure-conclusion only"
else
  fail "--failed filters to failure-conclusion only" "2 JSONL lines (test annotations)" "$line_count lines: $out"
fi

# Case 3: PR with no check-runs — exits 0 with no output
out=$(run_script 3)
ec=$?
if [[ $ec -eq 0 && -z "${out//[[:space:]]/}" ]]; then
  pass "empty check-runs exits 0 with no output"
else
  fail "empty check-runs exits 0 with no output" "exit 0 + empty out" "exit $ec, out: $out"
fi

# Case 4: Missing PR number — exits 1
run_script_silent
assert_exit "missing pr-number exits 1" 1 "$?"

# Case 5: gh pr view failure — exits 2
run_script_silent 2
assert_exit "gh pr view failure exits 2" 2 "$?"

# Case 8: per-check-run annotations API failure exits 2 (regression — `|| true`
# on the jq pipeline used to mask gh api auth/rate-limit failures and silently
# emit partial JSONL instead of failing the script per the docstring contract)
run_script_silent 5
assert_exit "annotations API failure exits 2" 2 "$?"

# Case 7: check-runs API failure exits 2 (regression — used to silently exit 0)
run_script_silent 4
assert_exit "check-runs API failure exits 2" 2 "$?"

# Case 6: JSONL output schema — every line valid JSON with required keys
out=$(run_script 1)
schema_ok=1
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if ! printf '%s' "$line" |
    jq -e 'has("check_run_id") and has("check_run_name") and has("level") and has("path") and has("start_line") and has("title") and has("message")' \
      >/dev/null 2>&1; then
    schema_ok=0
    break
  fi
done <<<"$out"
if [[ $schema_ok -eq 1 ]]; then
  pass "every JSONL line has required schema fields"
else
  fail "every JSONL line has required schema fields" "all lines pass jq schema check" "$out"
fi

# ---- Integration cases (opt-in: INTEGRATION=1) -----------------------------
#
# Hits real GitHub API against a known PR in this repo. Skipped by default.
# Run with: INTEGRATION=1 bash fetch-annotations.test.sh
# Optionally pin a specific PR: INTEGRATION_PR=999

if [[ "${INTEGRATION:-0}" == "1" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    skip_case "INTEGRATION mode but gh CLI not available"
  elif [[ -z "${GH_TOKEN:-}" ]]; then
    skip_case "INTEGRATION mode but GH_TOKEN not set"
  elif [[ -z "${INTEGRATION_REPO:-}" ]]; then
    skip_case "INTEGRATION mode but INTEGRATION_REPO not set (owner/name)"
  else
    # Default: query gh for the most recent merged PR. The script handles a
    # zero-annotations PR by exiting 0 with empty output (Case 3 covers that).
    REAL_PR="${INTEGRATION_PR:-}"
    if [[ -z "$REAL_PR" ]]; then
      REAL_PR=$(gh pr list --repo "$INTEGRATION_REPO" --state merged --limit 1 --json number --jq '.[0].number' 2>/dev/null | tr -d '\r\n')
    fi
    if [[ -z "$REAL_PR" || "$REAL_PR" == "null" ]]; then
      skip_case "INTEGRATION mode but could not resolve a merged PR"
    else
      out=$(FETCH_ANNOT_REPO="$INTEGRATION_REPO" \
        bash "$SCRIPT" "$REAL_PR" 2>&1)
      ec=$?
      # Pass criterion: exit 0 + (empty output OR every output line is valid JSON
      # with the expected schema). Empty is acceptable — many PRs have zero
      # annotations.
      schema_ok=1
      if [[ -n "${out//[[:space:]]/}" ]]; then
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          if ! printf '%s' "$line" |
            jq -e 'has("check_run_id") and has("level") and has("path")' \
              >/dev/null 2>&1; then
            schema_ok=0
            break
          fi
        done <<<"$out"
      fi
      if [[ $ec -eq 0 && $schema_ok -eq 1 ]]; then
        line_count=$(printf '%s\n' "$out" | grep -c '^{' || true)
        pass "INTEGRATION: PR #$REAL_PR returned $line_count annotations via API (schema OK)"
      else
        fail "INTEGRATION: PR #$REAL_PR via API" "exit 0 + schema OK" "exit $ec, schema_ok=$schema_ok, head: $(printf '%s' "$out" | head -3)"
      fi
    fi
  fi
fi

# Final
[[ $FAILED -eq 0 ]] || exit 1
exit 0
