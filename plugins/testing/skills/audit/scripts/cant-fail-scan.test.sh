#!/usr/bin/env bash
# Tests for cant-fail-scan.sh + cant-fail-scan.awk + mask-js.awk (self-contained;
# fixtures live in ../evals/fixtures/). Every fixture file is named here
# explicitly, so each is consumed by a grader (check-orphaned-fixtures.sh's
# contract), and every script the driver loads is named as a whole token so the
# affected-tests mapping reaches this suite from any of them.
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
  CANT_FAIL_SCAN_ROOT="$repo" bash "$SCAN" --findings </dev/null 2>/dev/null |
    LC_ALL=C grep -m1 '^branch:'
}

# EVERY git-reachable indicator character is asserted, not a sample. A
# four-name sample stayed green after `|`, `>`, `%`, backtick, `"` and `'`
# were dropped from this producer — the drift acceptance criterion 3 forbids.
# `-`, `?`, `:`, `[` and `*` are rejected by `git check-ref-format --branch`,
# so no checkout can reach them here; they are asserted against ai-slop's
# emitter, which takes --branch as an arbitrary string.
yb_slot=0
for b in ',foo' ']foo' '{foo' '}foo' '#foo' '&foo' '!foo' '|foo' '>foo' '%foo' '@foo' '`foo' "'foo"; do
  yb_slot=$((yb_slot + 1))
  got="$(yb_branch_line "$b" "$yb_slot")"
  want="branch: \"$b\""
  if [[ "$got" == "$want" ]]; then
    pass "indicator branch '$b' is emitted as a quoted scalar"
  else
    fail "indicator branch '$b' is emitted as a quoted scalar" "expected [$want], got [$got]"
  fi
done

# The double-quote indicator, whose expected form carries an escape.
yb_slot=$((yb_slot + 1))
got="$(yb_branch_line '"foo' "$yb_slot")"
if [[ "$got" == 'branch: "\"foo"' ]]; then
  pass 'indicator branch (leading double quote) is quoted and escaped'
else
  fail 'indicator branch (leading double quote) is quoted and escaped' "got [$got]"
fi

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

for b in true null 123 yes FALSE; do
  yb_slot=$((yb_slot + 1))
  got="$(yb_branch_line "$b" "$yb_slot")"
  want="branch: \"$b\""
  if [[ "$got" == "$want" ]]; then
    pass "implicit-type branch '$b' is quoted"
  else
    fail "implicit-type branch '$b' is quoted" "expected [$want], got [$got]"
  fi
done

# The quoting must survive a branch name carrying the quote character itself —
# otherwise the emitted scalar is quoted but unparsable, trading a silent drop
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

# --- playwright runner-config rules -------------------------------------------
# Engine: runner-config-scan.awk, loaded beside mask-js.awk, one config per
# invocation. Case directories live under ../evals/fixtures/config/ and hold a
# playwright.config.ts, .js, or .cjs; only config/scaffold/ also carries a test
# file (smoke.spec.ts), so it is the only tree --check can gate. Every other
# case is asserted on report-mode or --count stdout, never on an exit code that
# is 2 with and without the config rules. The one exception is the config-only
# --check block over config/commonjs/, which asserts exit 2 twice: those two
# exit assertions are regression guards on the unchanged 0-examined-test-files
# rule, and the discrimination in that block comes from the paired assertion on
# the appended config-findings message.

# config/scaffold/:the npm init playwright config verbatim: the retries
# expression fires, the forbidOnly idiom does not, and the spread inside a
# projects[] entry is too deep to decline the config.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/scaffold" bash "$SCAN" --check 2>&1)" || rc=$?
assert_exit "scaffold config tree gates clean without --strict (exit 0)" 0 "$rc"
assert_contains "scaffold playwright.config.ts fires flaky-passes-suite" "$out" "[testing/audit/rule-flaky-passes-suite]"
assert_contains "flaky detail names the retries expression, the absent guard, and the keys read" "$out" \
  "playwright.config.ts:21: retries: process.env.CI ? 2 : 0 at line 21 with failOnFlakyTests absent (8 depth-1 keys read)"
assert_not_contains "the scaffold's forbidOnly idiom passes (an expression is provably set)" "$out" "rule-only-not-forbidden"
assert_contains "the projects[] spread sits below depth 1 and does not decline the config" "$out" "rule-flaky-passes-suite"
assert_contains "smoke.spec.ts is the examined test file of the scaffold tree" "$out" "test files: 1 examined of 1 enumerated"
assert_contains "config findings are advisory in --check" "$out" "advisory in --check (use --strict"
assert_contains "the advisory note counts the config rules apart from mock-only-oracle" "$out" "mock-only-oracle 0, playwright config rules 1."
assert_contains "coverage reports the config denominator" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"
assert_contains "an advisory-only config finding still passes the gate" "$out" "PASS: no gating findings"

rc=0
CANT_FAIL_SCAN_ROOT="$FIX/config/scaffold" bash "$SCAN" --check --strict >/dev/null 2>&1 || rc=$?
assert_exit "--strict gates the config rules (exit 1)" 1 "$rc"

rc=0
n="$(CANT_FAIL_SCAN_ROOT="$FIX/config/scaffold" bash "$SCAN" --count 2>/dev/null)" || rc=$?
assert_exit "--count over the scaffold config tree completes" 0 "$rc"
if [[ "$n" == "1" ]]; then pass "--count over the scaffold config reports 1"; else fail "--count over the scaffold config reports 1" "got $n"; fi

# config/clean/:failOnFlakyTests: true and the forbidOnly idiom: both rules
# decline key-set.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/clean" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "clean config report completes" 0 "$rc"
assert_not_contains "a config with both guards set yields no finding" "$out" "finding ["
assert_contains "the clean config was examined, not skipped" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/forbid-false/:forbidOnly: false fires at its own line; retries: 0 is
# provably zero, so the flaky rule declines.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/forbid-false" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "forbid-false config report completes" 0 "$rc"
assert_contains "forbidOnly: false fires at its own line" "$out" "playwright.config.ts:5: forbidOnly: false at line 5"
assert_not_contains "a literal retries: 0 does not fire flaky-passes-suite" "$out" "rule-flaky-passes-suite"
n="$(count_lines "$out" '^finding \[')"
if [[ "$n" == "1" ]]; then pass "forbid-false yields exactly one finding"; else fail "forbid-false yields exactly one finding" "got $n"; fi

# config/no-retries/:neither key present: the absent forbidOnly fires at the
# anchor line and names the keys it read.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/no-retries" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "no-retries config report completes" 0 "$rc"
assert_contains "an absent forbidOnly fires at the anchor line with its denominator" "$out" \
  "playwright.config.ts:3: forbidOnly absent from the config object anchored at line 3 (2 depth-1 keys read)"
assert_not_contains "an absent retries key does not fire flaky-passes-suite" "$out" "rule-flaky-passes-suite"

# config/spread/:a depth-1 ...spread may override anything read, so both
# rules decline the whole config rather than fire on an absent key.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/spread" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "spread config report completes" 0 "$rc"
assert_not_contains "a top-level spread yields no finding" "$out" "finding ["
assert_contains "the spread config is still examined and counted" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/variadic/:a second defineConfig argument may override anything read.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/variadic" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "variadic config report completes" 0 "$rc"
assert_not_contains "a second defineConfig argument yields no finding" "$out" "finding ["
assert_contains "the variadic config is still examined and counted" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/reexport/:export default of an identifier: no object literal to
# read, and the later unrelated { retries: 3 } is never adopted.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/reexport" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "reexport config report completes" 0 "$rc"
assert_not_contains "a re-exported config yields no finding" "$out" "finding ["
assert_contains "an unanchorable config is a coverage boundary, not a decline" "$out" \
  "playwright configs: 0 examined of 1 enumerated (0 shadowed, 1 without a recognizable config object, 0 unreadable)"

# config/merge-arg/:defineConfig(baseConfig): the next token after the anchor
# is an identifier, not a {.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/merge-arg" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "merge-arg config report completes" 0 "$rc"
assert_not_contains "defineConfig over an identifier yields no finding" "$out" "finding ["
assert_contains "merge-arg is counted as enumerated and not examined" "$out" \
  "playwright configs: 0 examined of 1 enumerated (0 shadowed, 1 without a recognizable config object, 0 unreadable)"

# config/exempt/:cant-fail-ok: anywhere in the config suppresses every finding
# in it, counted rather than silent.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/exempt" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "exempt config report completes" 0 "$rc"
assert_not_contains "an annotated config emits no finding" "$out" "finding ["
assert_contains "the suppressed config finding is counted" "$out" "exempted findings (cant-fail-ok): 1"

# config/exempt-both/:a .cjs config firing both rules, annotated once: the
# annotation is file-scoped, so both findings are suppressed and both counted.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/exempt-both" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "exempt-both config report completes" 0 "$rc"
assert_not_contains "an annotated .cjs config emits no finding" "$out" "finding ["
assert_contains "one annotation suppresses and counts both config rules" "$out" "exempted findings (cant-fail-ok): 2"
assert_contains "a .cjs config is enumerated and examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/project-key/:forbidOnly below the top level has no runtime effect and
# no runtime claim is made about it: the rule declines instead of firing.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/project-key" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "project-key config report completes" 0 "$rc"
assert_contains "a top-level retries with no failOnFlakyTests still fires" "$out" \
  "playwright.config.ts:5: retries: 2 at line 5 with failOnFlakyTests absent (3 depth-1 keys read)"
assert_not_contains "a forbidOnly inside projects[] neither satisfies nor fires the rule" "$out" "rule-only-not-forbidden"
n="$(count_lines "$out" '^finding \[')"
if [[ "$n" == "1" ]]; then pass "project-key yields exactly one finding"; else fail "project-key yields exactly one finding" "got $n"; fi

# config/shadow/:two configs in one directory: playwright.config.ts wins the
# probe order and playwright.config.js is counted as shadowed, never read. The
# shadowed file would fire both rules, so reading it would show here.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/shadow" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "shadow config report completes" 0 "$rc"
assert_contains "only the first config in probe order is examined" "$out" \
  "playwright configs: 1 examined of 2 enumerated (1 shadowed, 0 without a recognizable config object, 0 unreadable)"
assert_not_contains "the shadowed playwright.config.js is never read" "$out" "finding ["

# config/quoted-keys/:the masker blanks a quoted key entirely, so the name is
# read from the raw line at the masked colon's column.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/quoted-keys" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "quoted-keys config report completes" 0 "$rc"
assert_not_contains "quoted guard keys are read and satisfy both rules" "$out" "finding ["
assert_contains "the quoted-keys config was examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/commonjs/:module.exports = { ... } in a playwright.config.js.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/commonjs" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "commonjs config report completes" 0 "$rc"
assert_contains "module.exports anchors the config object (flaky)" "$out" \
  "playwright.config.js:1: retries: 2 at line 1 with failOnFlakyTests absent (1 depth-1 keys read)"
assert_contains "module.exports anchors the config object (forbidOnly)" "$out" \
  "playwright.config.js:1: forbidOnly absent from the config object anchored at line 1 (1 depth-1 keys read)"
n="$(count_lines "$out" '^finding \[')"
if [[ "$n" == "2" ]]; then pass "commonjs yields exactly two findings"; else fail "commonjs yields exactly two findings" "got $n"; fi

# config/nested-retries/:a retries key in reporter options is not a runner
# retry setting and is not read.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/nested-retries" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "nested-retries config report completes" 0 "$rc"
assert_not_contains "a retries key in reporter options does not fire" "$out" "finding ["
assert_contains "the nested-retries config was examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/projects-retries/:per-project retries is legal and counts; one
# finding per config, located at the first counted occurrence.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/projects-retries" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "projects-retries config report completes" 0 "$rc"
assert_contains "per-project retries fires once, at the first occurrence, naming the cardinality" "$out" \
  "playwright.config.ts:9: retries: 2 at line 9 with failOnFlakyTests absent (3 depth-1 keys read); 3 retries occurrence(s)"
n="$(count_lines "$out" '^finding \[')"
if [[ "$n" == "1" ]]; then pass "projects-retries yields exactly one finding"; else fail "projects-retries yields exactly one finding" "got $n"; fi

# config/generic-anchor/:defineConfig<T>({...}) on one line, with a trailing
# satisfies clause that is not a second argument.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/generic-anchor" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "generic-anchor config report completes" 0 "$rc"
assert_contains "a generic defineConfig call anchors the config object (flaky)" "$out" \
  "playwright.config.ts:4: retries: 2 at line 4 with failOnFlakyTests absent (1 depth-1 keys read)"
assert_contains "a generic defineConfig call anchors the config object (forbidOnly)" "$out" \
  "playwright.config.ts:4: forbidOnly absent from the config object anchored at line 4 (1 depth-1 keys read)"
n="$(count_lines "$out" '^finding \[')"
if [[ "$n" == "2" ]]; then pass "generic-anchor yields exactly two findings"; else fail "generic-anchor yields exactly two findings" "got $n"; fi

# config/nested-retries-stale/: the projects context does not outlive its own
# depth-1 entry. A later key whose colon sits on another line is unreadable, and
# an unreadable key must inherit no context, or a retries under the NEXT key
# would be read as a per-project one.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/nested-retries-stale" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "nested-retries-stale config report completes" 0 "$rc"
assert_not_contains "a retries under a later key is not read as a projects[] entry's" "$out" "finding ["
assert_contains "the nested-retries-stale config was examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/helper-define/: a helper defineConfig call above the exported one is not
# the config the runner loads; the exported object, carrying a depth-1 spread,
# is, and it declines both rules.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/helper-define" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "helper-define config report completes" 0 "$rc"
assert_not_contains "a helper defineConfig object is never the anchor" "$out" "finding ["
assert_contains "the helper-define config was examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/split-value/: a value continued onto the next line leaves a ternary
# colon behind, which is not a key separator and must not inflate the depth-1
# key count the absent-guard detail reports.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/split-value" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "split-value config report completes" 0 "$rc"
assert_contains "a continued value registers no phantom depth-1 key" "$out" \
  "playwright.config.ts:6: retries: process.env.CI at line 6 with failOnFlakyTests absent (3 depth-1 keys read)"
n="$(count_lines "$out" '^finding \[')"
if [[ "$n" == "1" ]]; then pass "split-value yields exactly one finding"; else fail "split-value yields exactly one finding" "got $n"; fi

# config/generic-nested/: a generic argument that itself carries angle brackets
# still anchors the config object.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/generic-nested" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "generic-nested config report completes" 0 "$rc"
assert_contains "a nested generic argument anchors the config object (flaky)" "$out" \
  "playwright.config.ts:3: retries: 2 at line 3 with failOnFlakyTests absent (1 depth-1 keys read)"
assert_contains "a nested generic argument anchors the config object (forbidOnly)" "$out" \
  "playwright.config.ts:3: forbidOnly absent from the config object anchored at line 3 (1 depth-1 keys read)"
n="$(count_lines "$out" '^finding \[')"
if [[ "$n" == "2" ]]; then pass "generic-nested yields exactly two findings"; else fail "generic-nested yields exactly two findings" "got $n"; fi

# CRLF configs: the config engine strips its own \r, so a Windows checkout reads
# the same keys and values as a POSIX one.
CFGCRLF1="$TMP_ROOT/cfgcrlf1"
mkdir -p "$CFGCRLF1"
printf 'export default defineConfig({\r\n  retries: 2,\r\n});\r\n' >"$CFGCRLF1/playwright.config.ts"
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$CFGCRLF1" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "CRLF config scans" 0 "$rc"
assert_contains "CRLF retries value is read without the carriage return" "$out" "retries: 2 at line 2 with failOnFlakyTests absent"

CFGCRLF2="$TMP_ROOT/cfgcrlf2"
mkdir -p "$CFGCRLF2"
printf 'export default defineConfig({\r\n  forbidOnly: true,\r\n  retries: 0\r\n});\r\n' >"$CFGCRLF2/playwright.config.ts"
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$CFGCRLF2" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "CRLF config with both guards satisfied scans" 0 "$rc"
assert_not_contains "a CRLF literal 0 and a CRLF literal true are read as such" "$out" "finding ["
assert_contains "the CRLF config was examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

CFGCRLF3="$TMP_ROOT/cfgcrlf3"
mkdir -p "$CFGCRLF3"
printf 'export default defineConfig({\r\n  forbidOnly: false,\r\n  retries: 0,\r\n});\r\n' >"$CFGCRLF3/playwright.config.ts"
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$CFGCRLF3" bash "$SCAN" 2>&1)" || rc=$?
assert_exit "CRLF config with forbidOnly: false scans" 0 "$rc"
assert_contains "a CRLF literal false fires only-not-forbidden" "$out" "forbidOnly: false at line 2"

# A tree with test files and no Playwright config says the config rules do not
# apply rather than reporting a silent zero.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/negative" bash "$SCAN" --check 2>&1)" || rc=$?
assert_exit "negative tree still gates clean with the config rules present" 0 "$rc"
assert_contains "a tree with no Playwright config says the config rules are not applicable" "$out" \
  "playwright configs: 0 enumerated; config rules not applicable"

# A config-only tree: the exit-2 rule for 0 examined TEST files is unchanged,
# and the message names the config findings it reported but did not gate.
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/commonjs" bash "$SCAN" --check 2>&1)" || rc=$?
assert_exit "--check over a config-only tree still fails closed (exit 2)" 2 "$rc"
assert_contains "the config-only refusal names the config findings it reported" "$out" \
  "(2 config finding(s) were reported; they are not gated or persisted without an examined test file)"
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$FIX/config/commonjs" bash "$SCAN" --check --strict 2>&1)" || rc=$?
assert_exit "--strict does not turn a config-only tree into a gated failure (exit 2)" 2 "$rc"
assert_contains "--strict over a config-only tree still names the ungated findings" "$out" \
  "(2 config finding(s) were reported; they are not gated or persisted without an examined test file)"

CFGONLY="$TMP_ROOT/cfgonly-repo"
mkdir -p "$CFGONLY"
git -C "$TMP_ROOT" init -q -b cfgonly-branch cfgonly-repo
cp "$FIX/config/commonjs/playwright.config.js" "$CFGONLY/"
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$CFGONLY" bash "$SCAN" --findings 2>&1 >/dev/null)" || rc=$?
assert_exit "--findings over a config-only tree refuses (exit 2)" 2 "$rc"
assert_contains "the --findings refusal names the config findings it will not persist" "$out" \
  "(2 config finding(s) were reported; they are not gated or persisted without an examined test file)"

# --findings rows and the ## Surfaces line for the config rules.
CFGREPO="$TMP_ROOT/cfgrepo"
mkdir -p "$CFGREPO/e2e"
git -C "$TMP_ROOT" init -q -b cfg-branch cfgrepo
cp "$FIX/config/scaffold/playwright.config.ts" "$CFGREPO/"
cp "$FIX/config/scaffold/smoke.spec.ts" "$CFGREPO/e2e/"
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$CFGREPO" bash "$SCAN" --findings 2>/dev/null)" || rc=$?
assert_exit "--findings persists config findings alongside test findings" 0 "$rc"
assert_contains "config row carries IMPORTANT and omits Confidence, located at the config line" "$out" \
  "| IMPORTANT |  | playwright.config.ts:21 |"
assert_contains "config Finding cell leads with the qualified rule id" "$out" "testing/audit/rule-flaky-passes-suite: retries:"
assert_contains "config Finding cell carries the fired threshold" "$out" \
  "(threshold: retries > 0 or an expression, failOnFlakyTests absent or literal false)"
assert_contains "the flaky Action names the Playwright version floor for failOnFlakyTests" "$out" "1.52"
assert_contains "Surfaces carries the config denominator" "$out" "playwright configs: 1 examined of 1 enumerated"
assert_contains "Surfaces tallies config findings per rule" "$out" \
  "config findings: testing/audit/rule-flaky-passes-suite 1, testing/audit/rule-only-not-forbidden 0"
assert_contains "Surfaces tallies config declines per rule" "$out" \
  "config declined (examined, rule did not fire): rule-flaky-passes-suite 0, rule-only-not-forbidden 1"
assert_contains "the test-file surfaces counts stay where consumers read them" "$out" "testing/audit/rule-zero-assertion 0"

# The Surfaces line attributes one exemption to each suppressed config rule.
XREPO="$TMP_ROOT/xrepo"
mkdir -p "$XREPO/e2e"
git -C "$TMP_ROOT" init -q -b exempt-branch xrepo
cp "$FIX/config/exempt-both/playwright.config.cjs" "$XREPO/"
cp "$FIX/config/scaffold/smoke.spec.ts" "$XREPO/e2e/"
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$XREPO" bash "$SCAN" --findings 2>/dev/null)" || rc=$?
assert_exit "--findings over an annotated config completes" 0 "$rc"
assert_contains "Surfaces attributes one exemption to each config rule" "$out" \
  "config exempted via cant-fail-ok: rule-flaky-passes-suite 1, rule-only-not-forbidden 1"
assert_not_contains "an exempted config finding is never persisted as a row" "$out" "rule-flaky-passes-suite:"

# The exported object's depth-1 spread declines both rules, which is only
# visible in the Surfaces line.
HREPO="$TMP_ROOT/hrepo"
mkdir -p "$HREPO/e2e"
git -C "$TMP_ROOT" init -q -b helper-branch hrepo
cp "$FIX/config/helper-define/playwright.config.ts" "$HREPO/"
cp "$FIX/config/scaffold/smoke.spec.ts" "$HREPO/e2e/"
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$HREPO" bash "$SCAN" --findings 2>/dev/null)" || rc=$?
assert_exit "--findings over the helper-define config completes" 0 "$rc"
assert_contains "the exported object's spread declines both rules" "$out" \
  "config declined (examined, rule did not fire): rule-flaky-passes-suite 1, rule-only-not-forbidden 1"
assert_contains "no config finding is persisted from a declined config" "$out" \
  "config findings: testing/audit/rule-flaky-passes-suite 0, testing/audit/rule-only-not-forbidden 0"

# --- fail-closed: an unreadable playwright config is not a clean one ----------
# A config the walk enumerated but could not read is a coverage gap of its own:
# it is counted as a config, never as an unreadable test file, and the gate
# still refuses.
CFGUNREAD="$TMP_ROOT/cfgunread"
mkdir -p "$CFGUNREAD"
cp "$FIX/negative/discriminating-js.test.js" "$CFGUNREAD/"
cp "$FIX/config/commonjs/playwright.config.js" "$CFGUNREAD/"
chmod 000 "$CFGUNREAD/playwright.config.js" 2>/dev/null || true
if cat "$CFGUNREAD/playwright.config.js" >/dev/null 2>&1; then
  printf 'SKIP: unreadable-config case — chmod 000 not enforced on this filesystem (covered on CI'\''s Linux runners)\n'
else
  rc=0
  out="$(CANT_FAIL_SCAN_ROOT="$CFGUNREAD" bash "$SCAN" --check 2>&1)" || rc=$?
  assert_exit "--check fails closed on an unreadable playwright config (exit 2)" 2 "$rc"
  assert_contains "the fail-closed message names the unread input as a config" "$out" "1 unreadable playwright config(s)"
  assert_contains "an unreadable config stays in the config denominator" "$out" \
    "playwright configs: 0 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 1 unreadable)"
  assert_not_contains "an unreadable config is never reported as an unreadable test file" "$out" "1 unreadable test file(s)"
fi
chmod 600 "$CFGUNREAD/playwright.config.js" 2>/dev/null || true

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
