#!/usr/bin/env bash
# Tests for cant-fail-scan.sh + cant-fail-scan.awk (self-contained; fixtures
# live in ../evals/fixtures/). Every fixture file is named here explicitly, so
# each is consumed by a grader (check-orphaned-fixtures.sh's contract).
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

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
assert_matches() {
  # assert_matches <name> <haystack> <ERE>. Use this wherever the assertion is
  # about the SHAPE of a field's value: a substring check on a prefix of that
  # value passes for every malformed value sharing the prefix, which is the
  # can't-fail shape this scanner exists to find.
  if printf '%s\n' "$2" | LC_ALL=C grep -qE "$3"; then
    pass "$1"
  else
    fail "$1" "expected output to match ERE: $3"
  fi
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
# Location is repo-relative (the fixtures sit inside this repo), so the
# assertions anchor on the path SUFFIX plus the detail, never the full prefix.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/positive" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "positive report completes (exit 0 — advisory)" 0 "$rc"
assert_contains "zero-assertion rule id emitted" "$out" "[testing/audit/rule-zero-assertion]"
assert_contains "recomputed-expectation rule id emitted" "$out" "[testing/audit/rule-recomputed-expectation]"
assert_contains "mock-only-oracle rule id emitted" "$out" "[testing/audit/rule-mock-only-oracle]"
assert_contains "js string-shadowed tautology fires in cant-fail-js.test.js" "$out" "cant-fail-js.test.js:8: expect(double(2)) compared to itself"
assert_contains "js zero-assertion fires" "$out" "cant-fail-js.test.js:11: test 'adds numbers' has 0 assertion tokens"
assert_contains "js recomputed-expectation fires" "$out" "cant-fail-js.test.js:16: expect(formatUser({id:1})) compared to itself"
assert_contains "js mock-only-oracle fires" "$out" "cant-fail-js.test.js:23: test 'notifies the mailer': 1 mock-interaction assertion(s)"
assert_contains "py zero-assertion fires in test_cant_fail_py.py" "$out" "test_cant_fail_py.py:7: test 'test_add_runs' has 0 assertion tokens"
assert_contains "py recomputed-expectation fires" "$out" "test_cant_fail_py.py:12: assert add(2,3) == add(2,3)"
assert_contains "py mock-only-oracle fires" "$out" "test_cant_fail_py.py:15: test 'test_notify_calls_mailer': 1 mock-interaction assertion(s)"
assert_contains "cs zero-assertion fires in CantFailTests.cs" "$out" "CantFailTests.cs:8: test 'Charge_Runs' has 0 assertion tokens"
assert_contains "cs recomputed-expectation fires" "$out" "CantFailTests.cs:17: Assert.Equal(Format.User(1), Format.User(1))"
assert_contains "cs mock-only-oracle fires" "$out" "CantFailTests.cs:21: test 'Notify_Calls_Mailer': 1 mock-interaction assertion(s)"

n="$(count_lines "$out" '^finding \[')"
if [[ "$n" == "11" ]]; then pass "positive fixtures yield exactly 11 findings"; else fail "positive fixtures yield exactly 11 findings" "got $n"; fi

rc=0
n="$(CANT_FAIL_SCAN_ROOT="$FIX/positive" bash "$SCAN" --count 2>/dev/null)" || rc=$?
assert_exit "--count completes" 0 "$rc"
if [[ "$n" == "11" ]]; then pass "--count reports 11"; else fail "--count reports 11" "got $n"; fi

rc=0
CANT_FAIL_SCAN_ROOT="$FIX/positive" bash "$SCAN" --check >/dev/null 2>&1 || rc=$?
assert_exit "--check on positive fixtures fails (exit 1)" 1 "$rc"

# --- negative fixtures: the false-positive guard ------------------------------
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/negative" bash "$SCAN" --check 2>&1)" || rc=$?
assert_exit "--check on negative fixtures passes (exit 0)" 0 "$rc"
assert_not_contains "negative fixtures yield zero findings (discriminating-js.test.js, discriminating-ava.test.js, test_discriminating_py.py, DiscriminatingTests.cs)" "$out" "finding ["
assert_contains "negative run parsed real blocks (not a scan of nothing)" "$out" "test files: 4 examined of 4 enumerated"
assert_contains "negative run parsed every runnable block (a parser silently dropping blocks would show here)" "$out" "test blocks parsed: 19;"
assert_contains "negative run passes loudly" "$out" "PASS: no gating findings"
rc=0
CANT_FAIL_SCAN_ROOT="$FIX/negative" bash "$SCAN" --check --strict >/dev/null 2>&1 || rc=$?
assert_exit "--check --strict on negative fixtures still passes (mock-plus-value tests are not mock-only)" 0 "$rc"

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
# The `date:` value is a contract SHAPE, not a presence flag. `date: 20` also
# matches `date: 2026-08-21T13-36-00Z` — a hyphenated time that is ISO-8601 in
# neither the extended nor the basic profile — so it is the same assertion that
# pinned ai-slop's emitter bug instead of catching it (#3097). Anchoring the
# full extended form with an explicit `Z` makes a format-string regression in
# the emitter fail here.
assert_matches "date frontmatter is ISO-8601 extended UTC (YYYY-MM-DDThh:mm:ssZ)" "$out" \
  '^date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
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

# --- branch names that are YAML indicators ------------------------------------
#
# git accepts branch names beginning with a YAML indicator: `git check-ref-format
# --branch` calls "@foo", "!foo", "#foo" and "&foo" all valid. Emitted as a bare
# plain scalar, "#foo" and "&foo" parse to null and "@foo"/"!foo" are outright
# parse errors. The consumer (review/fanout fix-pass-mode.md "Step 1") admits a
# findings file only when its `branch:` value equals the current branch EXACTLY,
# so a misparse silently drops every finding for that branch — no error, and
# nothing distinguishing it from "no findings".
#
# This producer reads the CHECKED-OUT branch, so each case needs a real repo on
# a real branch rather than a flag. `*foo` is not a legal git branch name and so
# cannot be reached here; the predicate is asserted on it in ai-slop's suite,
# whose emitter takes --branch as an arbitrary string.
#
# Both directions are asserted. Quoting is CONDITIONAL, so an ordinary branch
# name must stay a byte-identical plain scalar: a helper that quoted
# unconditionally would pass a quoted-only assertion while moving the wire
# format for every ordinary branch.
yb_branch_line() {
  # yb_branch_line <branch> <slot> -> the emitted `branch:` frontmatter line
  local b="$1" slot="$2" repo="$TMP_ROOT/yb$2"
  mkdir -p "$repo"
  git -C "$TMP_ROOT" init -q -b "$b" "yb$slot" 2>/dev/null
  cp "$FIX/sanity/one-assertion-free.test.js" "$repo/"
  CANT_FAIL_SCAN_ROOT="$repo" bash "$SCAN" --findings 2>/dev/null |
    LC_ALL=C grep -m1 '^branch:'
}

yb_slot=0
for b in '@foo' '!foo' '#foo' '&foo'; do
  yb_slot=$((yb_slot + 1))
  got="$(yb_branch_line "$b" "$yb_slot")"
  want="branch: \"$b\""
  if [[ "$got" == "$want" ]]; then
    pass "indicator branch '$b' is emitted as a quoted scalar"
  else
    fail "indicator branch '$b' is emitted as a quoted scalar" "expected [$want], got [$got]"
  fi
done

for b in 'main' 'feat/3179-slug' 'release-1.2_x'; do
  yb_slot=$((yb_slot + 1))
  got="$(yb_branch_line "$b" "$yb_slot")"
  want="branch: $b"
  if [[ "$got" == "$want" ]]; then
    pass "ordinary branch '$b' stays an unquoted plain scalar"
  else
    fail "ordinary branch '$b' stays an unquoted plain scalar" "expected [$want], got [$got]"
  fi
done

# The quoting must survive a branch name carrying the quote character itself —
# otherwise the emitted scalar is quoted but unparseable, trading a silent drop
# for a hard consumer failure. (A backslash is not legal in a git branch name,
# so only the quote case is reachable through a real checkout here.)
yb_slot=$((yb_slot + 1))
got="$(yb_branch_line '@with"quote' "$yb_slot")"
if [[ "$got" == 'branch: "@with\"quote"' ]]; then
  pass "a quote character inside an indicator branch is escaped"
else
  fail "a quote character inside an indicator branch is escaped" "got [$got]"
fi

# report mode never claims a clean bill over nothing
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$EMPTY" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "report over an empty tree completes" 0 "$rc"
assert_contains "an empty scan is named a scan of nothing" "$out" "NOTHING TO AUDIT"
assert_not_contains "an empty scan is not a clean bill" "$out" "No can't-fail tests found."

# the gate refuses a scan of nothing — a wrong root and a healthy suite must
# not share exit 0
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$EMPTY" bash "$SCAN" --check 2>&1)" || rc=$?
assert_exit "--check over 0 examined test files fails closed (exit 2)" 2 "$rc"
assert_contains "empty-gate refusal says why" "$out" "0 test files were examined"
assert_not_contains "empty gate never prints PASS" "$out" "PASS:"

# Location is repo-relative even when the scan root narrows to a subdirectory
SUBREPO="$TMP_ROOT/subrepo"
mkdir -p "$SUBREPO/sub"
git -C "$TMP_ROOT" init -q -b sub-branch subrepo
printf 'test("v", () => { run(); });\n' >"$SUBREPO/sub/vacuous.test.js"
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$SUBREPO/sub" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "subdir-root scan completes" 0 "$rc"
assert_contains "Location keeps the repo prefix under a subdir scan root" "$out" "sub/vacuous.test.js:1:"

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
  assert_contains "fail-closed message names the unread input" "$out" "could not fully read"
fi
chmod 600 "$UNREAD/hidden.test.js" 2>/dev/null || true

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
