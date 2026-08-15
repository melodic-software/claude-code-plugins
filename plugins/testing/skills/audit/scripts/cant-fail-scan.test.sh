#!/usr/bin/env bash
# Tests for cant-fail-scan.sh + cant-fail-scan.awk (self-contained; fixtures
# live in ../evals/fixtures/). Every fixture file is named here explicitly, so
# each is consumed by a grader (check-orphaned-fixtures.sh's contract).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$SCRIPT_DIR/cant-fail-scan.sh"
FIX="$SCRIPT_DIR/../evals/fixtures"

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
assert_exit() {
  # assert_exit <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected output to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1" "expected output NOT to contain: $3" ;;
    *) pass "$1" ;;
  esac
}
count_lines() { printf '%s\n' "$1" | grep -c "$2"; }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# --- usage / environment gaps -------------------------------------------------
rc=0
bash "$SCAN" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

rc=0
bash "$SCAN" --bogus >/dev/null 2>&1 || rc=$?
assert_exit "unknown argument exits 2" 2 "$rc"

rc=0
CANT_FAIL_SCAN_ROOT="$TMP_ROOT/does-not-exist" bash "$SCAN" >/dev/null 2>&1 || rc=$?
assert_exit "nonexistent root refuses (exit 2)" 2 "$rc"

touch "$TMP_ROOT/a-file"
rc=0
CANT_FAIL_SCAN_ROOT="$TMP_ROOT/a-file" bash "$SCAN" >/dev/null 2>&1 || rc=$?
assert_exit "root that is a file refuses (exit 2)" 2 "$rc"

# --- positive fixtures: every rule fires, per ecosystem ------------------------
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/positive" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "positive report completes (exit 0 — advisory)" 0 "$rc"
assert_contains "js zero-assertion fires in cant-fail-js.test.js" "$out" "[testing/audit/rule-zero-assertion] cant-fail-js.test.js:5"
assert_contains "js recomputed-expectation fires" "$out" "[testing/audit/rule-recomputed-expectation] cant-fail-js.test.js:10"
assert_contains "js mock-only-oracle fires" "$out" "[testing/audit/rule-mock-only-oracle] cant-fail-js.test.js:17"
assert_contains "py zero-assertion fires in test_cant_fail_py.py" "$out" "[testing/audit/rule-zero-assertion] test_cant_fail_py.py:7"
assert_contains "py recomputed-expectation fires" "$out" "[testing/audit/rule-recomputed-expectation] test_cant_fail_py.py:12"
assert_contains "py mock-only-oracle fires" "$out" "[testing/audit/rule-mock-only-oracle] test_cant_fail_py.py:15"
assert_contains "cs zero-assertion fires in CantFailTests.cs" "$out" "[testing/audit/rule-zero-assertion] CantFailTests.cs:8"
assert_contains "cs recomputed-expectation fires" "$out" "[testing/audit/rule-recomputed-expectation] CantFailTests.cs:17"
assert_contains "cs mock-only-oracle fires" "$out" "[testing/audit/rule-mock-only-oracle] CantFailTests.cs:21"

n="$(count_lines "$out" '^finding \[')"
if [[ "$n" == "10" ]]; then pass "positive fixtures yield exactly 10 findings"; else fail "positive fixtures yield exactly 10 findings" "got $n"; fi

rc=0
n="$(CANT_FAIL_SCAN_ROOT="$FIX/positive" bash "$SCAN" --count 2>/dev/null)" || rc=$?
assert_exit "--count completes" 0 "$rc"
if [[ "$n" == "10" ]]; then pass "--count reports 10"; else fail "--count reports 10" "got $n"; fi

rc=0
CANT_FAIL_SCAN_ROOT="$FIX/positive" bash "$SCAN" --check >/dev/null 2>&1 || rc=$?
assert_exit "--check on positive fixtures fails (exit 1)" 1 "$rc"

# --- negative fixtures: the false-positive guard ------------------------------
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/negative" bash "$SCAN" --check 2>&1)" || rc=$?
assert_exit "--check on negative fixtures passes (exit 0)" 0 "$rc"
assert_not_contains "negative fixtures yield zero findings (discriminating-js.test.js, test_discriminating_py.py, DiscriminatingTests.cs)" "$out" "finding ["
assert_contains "negative run parsed real blocks (not a scan of nothing)" "$out" "test files: 3 examined of 3 enumerated"
assert_contains "negative run passes loudly" "$out" "PASS: no gating findings"

# --- sanity fixture: the issue's settlement shape -----------------------------
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/sanity" bash "$SCAN" --check 2>&1)" || rc=$?
assert_exit "--check on one-assertion-free.test.js fails (exit 1)" 1 "$rc"
n="$(count_lines "$out" '^finding \[')"
if [[ "$n" == "1" ]]; then pass "sanity fixture yields exactly one finding"; else fail "sanity fixture yields exactly one finding" "got $n"; fi
assert_contains "sanity finding is the zero-assertion rule" "$out" "testing/audit/rule-zero-assertion"

# --- exemption annotation ------------------------------------------------------
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/exempt" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "exempt fixture report completes" 0 "$rc"
assert_not_contains "exempted-js.test.js emits no finding" "$out" "finding ["
assert_contains "exemption is counted, never silent" "$out" "exempted findings (cant-fail-ok): 1"

# --- mock-only-oracle is advisory unless --strict -----------------------------
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/mock-only" bash "$SCAN" --check 2>&1)" || rc=$?
assert_exit "mock-only-js.test.js does not gate by default (exit 0)" 0 "$rc"
assert_contains "advisory note names the escalation flag" "$out" "advisory in --check (use --strict"
assert_contains "the finding is still reported" "$out" "testing/audit/rule-mock-only-oracle"
rc=0
CANT_FAIL_SCAN_ROOT="$FIX/mock-only" bash "$SCAN" --check --strict >/dev/null 2>&1 || rc=$?
assert_exit "--strict gates mock-only-oracle (exit 1)" 1 "$rc"

# --- findings mode: detector-findings conformance -----------------------------
REPO="$TMP_ROOT/repo"
mkdir -p "$REPO/tests"
git -C "$TMP_ROOT" init -q -b findings-branch repo
cp "$FIX/sanity/one-assertion-free.test.js" "$REPO/tests/"
cp "$FIX/positive/cant-fail-js.test.js" "$REPO/tests/"

rc=0
out="$(CANT_FAIL_SCAN_ROOT="$REPO" bash "$SCAN" --findings 2>/dev/null)" || rc=$?
assert_exit "--findings completes in a git repo" 0 "$rc"
assert_contains "frontmatter declares the findings type" "$out" "type: review-findings"
assert_contains "branch frontmatter is the checked-out branch, verbatim" "$out" "branch: findings-branch"
assert_contains "date frontmatter is present" "$out" "date: 20"
assert_not_contains "tier: is omitted (no lifecycle-tier analogue)" "$out" "tier:"
assert_contains "table header matches the consumed shape" "$out" "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |"
assert_contains "row carries tier and confidence" "$out" "| IMPORTANT | high |"
assert_contains "Location is root-relative file:line" "$out" "tests/one-assertion-free.test.js:5"
assert_contains "Finding cell leads with the qualified rule id" "$out" "testing/audit/rule-zero-assertion:"
assert_contains "Surface(s) names this producer" "$out" "testing:audit"
assert_contains "coverage section present" "$out" "## Surfaces"
assert_contains "cell escaping: literal pipes in an expression are escaped" "$out" 'left\|\|right'
assert_contains "mock-only-oracle row omits Confidence rather than saying low" "$out" "| IMPORTANT |  |"
assert_not_contains "Confidence low is never emitted" "$out" "| low |"

# a run that examined files and found nothing still persists coverage
CLEAN="$TMP_ROOT/clean-repo"
mkdir -p "$CLEAN"
git -C "$TMP_ROOT" init -q -b clean-branch clean-repo
cp "$FIX/negative/discriminating-js.test.js" "$CLEAN/"
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$CLEAN" bash "$SCAN" --findings 2>/dev/null)" || rc=$?
assert_exit "--findings with zero findings still emits (coverage is the payload)" 0 "$rc"
assert_contains "empty table header still present" "$out" "| Rank | Tier | Confidence |"
assert_contains "surfaces line reports zero findings" "$out" "testing/audit/rule-zero-assertion 0"

# refusals: no branch, and nothing examined
NOGIT="$TMP_ROOT/nogit"
mkdir -p "$NOGIT"
cp "$FIX/sanity/one-assertion-free.test.js" "$NOGIT/"
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$NOGIT" bash "$SCAN" --findings 2>&1 >/dev/null)" || rc=$?
assert_exit "--findings without a checked-out branch refuses (exit 2)" 2 "$rc"
assert_contains "branch refusal names the reason" "$out" "checked-out branch"

EMPTY="$TMP_ROOT/empty-repo"
mkdir -p "$EMPTY"
git -C "$TMP_ROOT" init -q -b empty-branch empty-repo
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$EMPTY" bash "$SCAN" --findings 2>&1 >/dev/null)" || rc=$?
assert_exit "--findings over nothing examined refuses (exit 2)" 2 "$rc"
assert_contains "nothing-examined refusal says why" "$out" "0 test files were examined"

# report mode never claims a clean bill over nothing
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$EMPTY" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "report over an empty tree completes" 0 "$rc"
assert_contains "an empty scan is named a scan of nothing" "$out" "NOTHING TO AUDIT"
assert_not_contains "an empty scan is not a clean bill" "$out" "No can't-fail tests found."

# --- CRLF input ---------------------------------------------------------------
CRLF="$TMP_ROOT/crlf"
mkdir -p "$CRLF"
printf 'test("crlf case", () => {\r\n  run();\r\n});\r\n' >"$CRLF/crlf-case.test.js"
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$CRLF" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "CRLF file scans" 0 "$rc"
assert_contains "CRLF assertion-free test is detected" "$out" "testing/audit/rule-zero-assertion"

# --- fail-closed: an unreadable input is not a clean one ----------------------
UNREAD="$TMP_ROOT/unread"
mkdir -p "$UNREAD"
cp "$FIX/negative/discriminating-js.test.js" "$UNREAD/"
printf 'test("hidden", () => { run(); });\n' >"$UNREAD/hidden.test.js"
chmod 000 "$UNREAD/hidden.test.js" 2>/dev/null || true
if cat "$UNREAD/hidden.test.js" >/dev/null 2>&1; then
  # Filesystems that do not enforce mode 000 (Windows Git Bash) cannot host
  # this case; say so visibly rather than green-lighting an unexercised branch.
  printf 'SKIP: unreadable-input case — chmod 000 not enforced on this filesystem (covered on CI'\''s Linux runners)\n'
else
  rc=0
  out="$(CANT_FAIL_SCAN_ROOT="$UNREAD" bash "$SCAN" --check 2>&1)" || rc=$?
  assert_exit "--check fails closed on an unreadable test file (exit 2)" 2 "$rc"
  assert_contains "fail-closed message names the unread input" "$out" "could not be read"
fi
chmod 600 "$UNREAD/hidden.test.js" 2>/dev/null || true

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
