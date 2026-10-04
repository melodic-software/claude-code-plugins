#!/usr/bin/env bash
# Tests for cant-fail-scan.sh + cant-fail-scan.awk + mask-js.awk (self-contained;
# fixtures live in ../evals/fixtures/). Every fixture file is named here
# explicitly, so each is consumed by a grader (check-orphaned-fixtures.sh's
# contract), and every script the driver loads is named as a whole token so the
# affected-tests mapping reaches this suite from any of them.
# shellcheck disable=SC2016  # single-quoted fixture text is literal shell source
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

# run_scan <root> [args...]: scan <root>, leaving the COMBINED output in $out
# and the exit code in $rc. The few cases that assert on one channel alone keep
# their own explicit redirection instead.
run_scan() {
  local root="$1"
  shift
  rc=0
  out="$(CANT_FAIL_SCAN_ROOT="$root" bash "$SCAN" "$@" 2>&1)" || rc=$?
}

# assert_finding_count <name> <expected>: findings printed on $out.
assert_finding_count() {
  local n
  n="$(count_lines "$out" '^finding \[')"
  if [[ "$n" == "$2" ]]; then pass "$1"; else fail "$1" "got $n"; fi
}

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
run_scan "$FIX/positive"
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

assert_finding_count "positive fixtures yield exactly 11 findings" 11

rc=0
n="$(CANT_FAIL_SCAN_ROOT="$FIX/positive" bash "$SCAN" --count 2>/dev/null)" || rc=$?
assert_exit "--count completes" 0 "$rc"
if [[ "$n" == "11" ]]; then pass "--count reports 11"; else fail "--count reports 11" "got $n"; fi

rc=0
CANT_FAIL_SCAN_ROOT="$FIX/positive" bash "$SCAN" --check >/dev/null 2>&1 || rc=$?
assert_exit "--check on positive fixtures fails (exit 1)" 1 "$rc"

# --- negative fixtures: the false-positive guard ------------------------------
run_scan "$FIX/negative" --check
assert_exit "--check on negative fixtures passes (exit 0)" 0 "$rc"
assert_not_contains "negative fixtures yield zero findings (discriminating-js.test.js, discriminating-ava.test.js, test_discriminating_py.py, DiscriminatingTests.cs)" "$out" "finding ["
assert_contains "negative run parsed real blocks (not a scan of nothing)" "$out" "test files: 4 examined of 4 enumerated"
assert_contains "negative run parsed every runnable block (a parser silently dropping blocks would show here)" "$out" "test blocks parsed: 19;"
assert_contains "negative run passes loudly" "$out" "PASS: no gating findings"
rc=0
CANT_FAIL_SCAN_ROOT="$FIX/negative" bash "$SCAN" --check --strict >/dev/null 2>&1 || rc=$?
assert_exit "--check --strict on negative fixtures still passes (mock-plus-value tests are not mock-only)" 0 "$rc"

# --- sanity fixture: the issue's settlement shape -----------------------------
run_scan "$FIX/sanity" --check
assert_exit "--check on one-assertion-free.test.js fails (exit 1)" 1 "$rc"
assert_finding_count "sanity fixture yields exactly one finding" 1
assert_contains "sanity finding is the zero-assertion rule" "$out" "testing/audit/rule-zero-assertion"

# --- exemption annotation ------------------------------------------------------
run_scan "$FIX/exempt"
assert_exit "exempt fixture report completes" 0 "$rc"
assert_not_contains "exempted-js.test.js emits no finding" "$out" "finding ["
assert_contains "exemption is counted, never silent" "$out" "exempted findings (cant-fail-ok): 1"

# --- mock-only-oracle is advisory unless --strict -----------------------------
run_scan "$FIX/mock-only" --check
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
run_scan "$EMPTY"
assert_exit "report over an empty tree completes" 0 "$rc"
assert_contains "an empty scan is named a scan of nothing" "$out" "NOTHING TO AUDIT"
assert_not_contains "an empty scan is not a clean bill" "$out" "No can't-fail tests found."

# the gate refuses a scan of nothing — a wrong root and a healthy suite must
# not share exit 0
run_scan "$EMPTY" --check
assert_exit "--check over 0 examined test files fails closed (exit 2)" 2 "$rc"
assert_contains "empty-gate refusal says why" "$out" "0 test files were examined"
assert_not_contains "empty gate never prints PASS" "$out" "PASS:"

# Location is repo-relative even when the scan root narrows to a subdirectory
SUBREPO="$TMP_ROOT/subrepo"
mkdir -p "$SUBREPO/sub"
git -C "$TMP_ROOT" init -q -b sub-branch subrepo
printf 'test("v", () => { run(); });\n' >"$SUBREPO/sub/vacuous.test.js"
run_scan "$SUBREPO/sub"
assert_exit "subdir-root scan completes" 0 "$rc"
assert_contains "Location keeps the repo prefix under a subdir scan root" "$out" "sub/vacuous.test.js:1:"

# --- CRLF input ---------------------------------------------------------------
CRLF="$TMP_ROOT/crlf"
mkdir -p "$CRLF"
printf 'test("crlf case", () => {\r\n  run();\r\n});\r\n' >"$CRLF/crlf-case.test.js"
run_scan "$CRLF"
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
  run_scan "$UNREAD" --check
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
run_scan "$FIX/config/scaffold" --check
assert_exit "scaffold config tree gates clean without --strict (exit 0)" 0 "$rc"
assert_contains "scaffold playwright.config.ts fires flaky-passes-suite" "$out" "[testing/audit/rule-flaky-passes-suite]"
assert_contains "flaky detail names the retries expression, the absent guard, and the keys read" "$out" \
  "playwright.config.ts:21: retries: process.env.CI ? 2 : 0 at line 21 with failOnFlakyTests absent (8 depth-1 keys read)"
assert_not_contains "the scaffold's forbidOnly idiom passes (an expression is provably set)" "$out" "rule-only-not-forbidden"
assert_contains "the projects[] spread sits below depth 1 and does not decline the config" "$out" "rule-flaky-passes-suite"
assert_contains "smoke.spec.ts is the examined test file of the scaffold tree" "$out" "test files: 1 examined of 1 enumerated"
assert_contains "config findings are advisory in --check" "$out" "advisory in --check (use --strict"
assert_contains "the advisory note counts the config rules apart from mock-only-oracle" "$out" "mock-only-oracle 0, playwright config rules 1, advisory adapters (bash-bats, bash-harness) 0."
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
run_scan "$FIX/config/clean"
assert_exit "clean config report completes" 0 "$rc"
assert_not_contains "a config with both guards set yields no finding" "$out" "finding ["
assert_contains "the clean config was examined, not skipped" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/forbid-false/:forbidOnly: false fires at its own line; retries: 0 is
# provably zero, so the flaky rule declines.
run_scan "$FIX/config/forbid-false"
assert_exit "forbid-false config report completes" 0 "$rc"
assert_contains "forbidOnly: false fires at its own line" "$out" "playwright.config.ts:5: forbidOnly: false at line 5"
assert_not_contains "a literal retries: 0 does not fire flaky-passes-suite" "$out" "rule-flaky-passes-suite"
assert_finding_count "forbid-false yields exactly one finding" 1

# config/no-retries/:neither key present: the absent forbidOnly fires at the
# anchor line and names the keys it read.
run_scan "$FIX/config/no-retries"
assert_exit "no-retries config report completes" 0 "$rc"
assert_contains "an absent forbidOnly fires at the anchor line with its denominator" "$out" \
  "playwright.config.ts:3: forbidOnly absent from the config object anchored at line 3 (2 depth-1 keys read)"
assert_not_contains "an absent retries key does not fire flaky-passes-suite" "$out" "rule-flaky-passes-suite"

# config/spread/:a depth-1 ...spread may override anything read, so both
# rules decline the whole config rather than fire on an absent key.
run_scan "$FIX/config/spread"
assert_exit "spread config report completes" 0 "$rc"
assert_not_contains "a top-level spread yields no finding" "$out" "finding ["
assert_contains "the spread config is still examined and counted" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/variadic/:a second defineConfig argument may override anything read.
run_scan "$FIX/config/variadic"
assert_exit "variadic config report completes" 0 "$rc"
assert_not_contains "a second defineConfig argument yields no finding" "$out" "finding ["
assert_contains "the variadic config is still examined and counted" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/reexport/:export default of an identifier: no object literal to
# read, and the later unrelated { retries: 3 } is never adopted.
run_scan "$FIX/config/reexport"
assert_exit "reexport config report completes" 0 "$rc"
assert_not_contains "a re-exported config yields no finding" "$out" "finding ["
assert_contains "an unanchorable config is a coverage boundary, not a decline" "$out" \
  "playwright configs: 0 examined of 1 enumerated (0 shadowed, 1 without a recognizable config object, 0 unreadable)"

# config/merge-arg/:defineConfig(baseConfig): the next token after the anchor
# is an identifier, not a {.
run_scan "$FIX/config/merge-arg"
assert_exit "merge-arg config report completes" 0 "$rc"
assert_not_contains "defineConfig over an identifier yields no finding" "$out" "finding ["
assert_contains "merge-arg is counted as enumerated and not examined" "$out" \
  "playwright configs: 0 examined of 1 enumerated (0 shadowed, 1 without a recognizable config object, 0 unreadable)"

# config/exempt/:cant-fail-ok: anywhere in the config suppresses every finding
# in it, counted rather than silent.
run_scan "$FIX/config/exempt"
assert_exit "exempt config report completes" 0 "$rc"
assert_not_contains "an annotated config emits no finding" "$out" "finding ["
assert_contains "the suppressed config finding is counted" "$out" "exempted findings (cant-fail-ok): 1"

# config/exempt-both/:a .cjs config firing both rules, annotated once: the
# annotation is file-scoped, so both findings are suppressed and both counted.
run_scan "$FIX/config/exempt-both"
assert_exit "exempt-both config report completes" 0 "$rc"
assert_not_contains "an annotated .cjs config emits no finding" "$out" "finding ["
assert_contains "one annotation suppresses and counts both config rules" "$out" "exempted findings (cant-fail-ok): 2"
assert_contains "a .cjs config is enumerated and examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/project-key/:forbidOnly below the top level has no runtime effect and
# no runtime claim is made about it: the rule declines instead of firing.
run_scan "$FIX/config/project-key"
assert_exit "project-key config report completes" 0 "$rc"
assert_contains "a top-level retries with no failOnFlakyTests still fires" "$out" \
  "playwright.config.ts:5: retries: 2 at line 5 with failOnFlakyTests absent (3 depth-1 keys read)"
assert_not_contains "a forbidOnly inside projects[] neither satisfies nor fires the rule" "$out" "rule-only-not-forbidden"
assert_finding_count "project-key yields exactly one finding" 1

# config/shadow/:two configs in one directory: playwright.config.ts wins the
# probe order and playwright.config.js is counted as shadowed, never read. The
# shadowed file would fire both rules, so reading it would show here.
run_scan "$FIX/config/shadow"
assert_exit "shadow config report completes" 0 "$rc"
assert_contains "only the first config in probe order is examined" "$out" \
  "playwright configs: 1 examined of 2 enumerated (1 shadowed, 0 without a recognizable config object, 0 unreadable)"
assert_not_contains "the shadowed playwright.config.js is never read" "$out" "finding ["

# config/quoted-keys/:the masker blanks a quoted key entirely, so the name is
# read from the raw line at the masked colon's column.
run_scan "$FIX/config/quoted-keys"
assert_exit "quoted-keys config report completes" 0 "$rc"
assert_not_contains "quoted guard keys are read and satisfy both rules" "$out" "finding ["
assert_contains "the quoted-keys config was examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/commonjs/:module.exports = { ... } in a playwright.config.js.
run_scan "$FIX/config/commonjs"
assert_exit "commonjs config report completes" 0 "$rc"
assert_contains "module.exports anchors the config object (flaky)" "$out" \
  "playwright.config.js:1: retries: 2 at line 1 with failOnFlakyTests absent (1 depth-1 keys read)"
assert_contains "module.exports anchors the config object (forbidOnly)" "$out" \
  "playwright.config.js:1: forbidOnly absent from the config object anchored at line 1 (1 depth-1 keys read)"
assert_finding_count "commonjs yields exactly two findings" 2

# config/nested-retries/:a retries key in reporter options is not a runner
# retry setting and is not read.
run_scan "$FIX/config/nested-retries"
assert_exit "nested-retries config report completes" 0 "$rc"
assert_not_contains "a retries key in reporter options does not fire" "$out" "finding ["
assert_contains "the nested-retries config was examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/projects-retries/:per-project retries is legal and counts; one
# finding per config, located at the first counted occurrence.
run_scan "$FIX/config/projects-retries"
assert_exit "projects-retries config report completes" 0 "$rc"
assert_contains "per-project retries fires once, at the first occurrence, naming the cardinality" "$out" \
  "playwright.config.ts:9: retries: 2 at line 9 with failOnFlakyTests absent (3 depth-1 keys read); 3 retries occurrence(s)"
assert_finding_count "projects-retries yields exactly one finding" 1

# config/generic-anchor/:defineConfig<T>({...}) on one line, with a trailing
# satisfies clause that is not a second argument.
run_scan "$FIX/config/generic-anchor"
assert_exit "generic-anchor config report completes" 0 "$rc"
assert_contains "a generic defineConfig call anchors the config object (flaky)" "$out" \
  "playwright.config.ts:4: retries: 2 at line 4 with failOnFlakyTests absent (1 depth-1 keys read)"
assert_contains "a generic defineConfig call anchors the config object (forbidOnly)" "$out" \
  "playwright.config.ts:4: forbidOnly absent from the config object anchored at line 4 (1 depth-1 keys read)"
assert_finding_count "generic-anchor yields exactly two findings" 2

# config/nested-retries-stale/: the projects context does not outlive its own
# depth-1 entry. A later key whose colon sits on another line is unreadable, and
# an unreadable key must inherit no context, or a retries under the NEXT key
# would be read as a per-project one.
run_scan "$FIX/config/nested-retries-stale"
assert_exit "nested-retries-stale config report completes" 0 "$rc"
assert_not_contains "a retries under a later key is not read as a projects[] entry's" "$out" "finding ["
assert_contains "the nested-retries-stale config was examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/helper-define/: a helper defineConfig call above the exported one is not
# the config the runner loads; the exported object, carrying a depth-1 spread,
# is, and it declines both rules.
run_scan "$FIX/config/helper-define"
assert_exit "helper-define config report completes" 0 "$rc"
assert_not_contains "a helper defineConfig object is never the anchor" "$out" "finding ["
assert_contains "the helper-define config was examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# config/split-value/: a value continued onto the next line leaves a ternary
# colon behind, which is not a key separator and must not inflate the depth-1
# key count the absent-guard detail reports.
run_scan "$FIX/config/split-value"
assert_exit "split-value config report completes" 0 "$rc"
assert_contains "a continued value registers no phantom depth-1 key" "$out" \
  "playwright.config.ts:6: retries: process.env.CI at line 6 with failOnFlakyTests absent (3 depth-1 keys read)"
assert_finding_count "split-value yields exactly one finding" 1

# config/generic-nested/: a generic argument that itself carries angle brackets
# still anchors the config object.
run_scan "$FIX/config/generic-nested"
assert_exit "generic-nested config report completes" 0 "$rc"
assert_contains "a nested generic argument anchors the config object (flaky)" "$out" \
  "playwright.config.ts:3: retries: 2 at line 3 with failOnFlakyTests absent (1 depth-1 keys read)"
assert_contains "a nested generic argument anchors the config object (forbidOnly)" "$out" \
  "playwright.config.ts:3: forbidOnly absent from the config object anchored at line 3 (1 depth-1 keys read)"
assert_finding_count "generic-nested yields exactly two findings" 2

# config/multiline-guard/: a guard whose value sits on the next line is still
# that guard's value. Reading only the key's own line leaves the value empty,
# which reads as an expression, so a false guard would pass as set.
run_scan "$FIX/config/multiline-guard"
assert_exit "multiline-guard config report completes" 0 "$rc"
assert_contains "a failOnFlakyTests: false written on the next line is read as false" "$out" \
  "playwright.config.ts:5: retries: 2 at line 5 with failOnFlakyTests: false at line 6"
assert_contains "a forbidOnly: false written on the next line fires at the key's line" "$out" \
  "playwright.config.ts:8: forbidOnly: false at line 8"
assert_finding_count "multiline-guard yields exactly two findings" 2

# config/duplicate-guard/: a duplicate key at depth 1 resolves to the LAST
# occurrence at runtime, so that is the one each guard is classified from and
# anchored at.
run_scan "$FIX/config/duplicate-guard"
assert_exit "duplicate-guard config report completes" 0 "$rc"
assert_contains "the last failOnFlakyTests wins and anchors the flaky detail" "$out" \
  "playwright.config.js:2: retries: 2 at line 2 with failOnFlakyTests: false at line 6"
assert_contains "the last forbidOnly wins and anchors its own finding" "$out" \
  "playwright.config.js:7: forbidOnly: false at line 7"
assert_finding_count "duplicate-guard yields exactly two findings" 2

# config/multiline-retries-zero/: a literal 0 written on the next line is a
# provable zero, so the flaky shape is out of reach and neither rule fires.
run_scan "$FIX/config/multiline-retries-zero"
assert_exit "multiline-retries-zero config report completes" 0 "$rc"
assert_not_contains "a continued retries: 0 with both guards set yields no finding" "$out" "finding ["
assert_contains "the multiline-retries-zero config was examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# The same continued zero with no failOnFlakyTests key: nothing declines the
# flaky rule ahead of the retries value, so this is where an unread continuation
# shows up as a spurious finding.
CFGZERO="$TMP_ROOT/cfgzero"
mkdir -p "$CFGZERO"
printf 'export default defineConfig({\n  forbidOnly: true,\n  retries:\n    0,\n});\n' >"$CFGZERO/playwright.config.ts"
run_scan "$CFGZERO"
assert_exit "continued retries: 0 without a flaky guard scans" 0 "$rc"
assert_not_contains "a continued retries: 0 does not fire flaky-passes-suite" "$out" "finding ["
assert_contains "the continued-zero config was examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

# CRLF configs: the config engine strips its own \r, so a Windows checkout reads
# the same keys and values as a POSIX one.
CFGCRLF1="$TMP_ROOT/cfgcrlf1"
mkdir -p "$CFGCRLF1"
printf 'export default defineConfig({\r\n  retries: 2,\r\n});\r\n' >"$CFGCRLF1/playwright.config.ts"
run_scan "$CFGCRLF1"
assert_exit "CRLF config scans" 0 "$rc"
assert_contains "CRLF retries value is read without the carriage return" "$out" "retries: 2 at line 2 with failOnFlakyTests absent"

CFGCRLF2="$TMP_ROOT/cfgcrlf2"
mkdir -p "$CFGCRLF2"
printf 'export default defineConfig({\r\n  forbidOnly: true,\r\n  retries: 0\r\n});\r\n' >"$CFGCRLF2/playwright.config.ts"
run_scan "$CFGCRLF2"
assert_exit "CRLF config with both guards satisfied scans" 0 "$rc"
assert_not_contains "a CRLF literal 0 and a CRLF literal true are read as such" "$out" "finding ["
assert_contains "the CRLF config was examined" "$out" \
  "playwright configs: 1 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 0 unreadable)"

CFGCRLF3="$TMP_ROOT/cfgcrlf3"
mkdir -p "$CFGCRLF3"
printf 'export default defineConfig({\r\n  forbidOnly: false,\r\n  retries: 0,\r\n});\r\n' >"$CFGCRLF3/playwright.config.ts"
run_scan "$CFGCRLF3"
assert_exit "CRLF config with forbidOnly: false scans" 0 "$rc"
assert_contains "a CRLF literal false fires only-not-forbidden" "$out" "forbidOnly: false at line 2"

# A tree with test files and no Playwright config says the config rules do not
# apply rather than reporting a silent zero.
run_scan "$FIX/negative" --check
assert_exit "negative tree still gates clean with the config rules present" 0 "$rc"
assert_contains "a tree with no Playwright config says the config rules are not applicable" "$out" \
  "playwright configs: 0 enumerated; config rules not applicable"

# A config-only tree: the exit-2 rule for 0 examined TEST files is unchanged,
# and the message names the config findings it reported but did not gate.
run_scan "$FIX/config/commonjs" --check
assert_exit "--check over a config-only tree still fails closed (exit 2)" 2 "$rc"
assert_contains "the config-only refusal names the config findings it reported" "$out" \
  "(2 config finding(s) were reported; they are not gated or persisted without an examined test file)"
run_scan "$FIX/config/commonjs" --check --strict
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
  run_scan "$CFGUNREAD" --check
  assert_exit "--check fails closed on an unreadable playwright config (exit 2)" 2 "$rc"
  assert_contains "the fail-closed message names the unread input as a config" "$out" "1 unreadable playwright config(s)"
  assert_contains "an unreadable config stays in the config denominator" "$out" \
    "playwright configs: 0 examined of 1 enumerated (0 shadowed, 0 without a recognizable config object, 1 unreadable)"
  assert_not_contains "an unreadable config is never reported as an unreadable test file" "$out" "1 unreadable test file(s)"
fi
chmod 600 "$CFGUNREAD/playwright.config.js" 2>/dev/null || true

# --- --file: scan exactly one file ---------------------------------------------
# One file, the same exit codes as a whole-tree scan, repo-relative Location,
# and no evals/fixtures prune: the path was named, so it is scanned.
run_file() {
  rc=0
  out="$(bash "$SCAN" "$@" 2>&1)" || rc=$?
}
run_file --file "$FIX/positive/cant-fail-js.test.js"
assert_exit "--file report completes (exit 0)" 0 "$rc"
assert_contains "--file keeps Location repo-relative" "$out" \
  "plugins/testing/skills/audit/evals/fixtures/positive/cant-fail-js.test.js:11: test 'adds numbers' has 0 assertion tokens"
assert_not_contains "--file scans only the named file" "$out" "test_cant_fail_py.py"
assert_contains "--file denominator is one file" "$out" "test files: 1 examined of 1 enumerated"
run_file --file "$FIX/positive/CantFailTests.cs" --check
assert_exit "--file --check exits 1 on a gating finding" 1 "$rc"
run_file --check --file "$FIX/negative/test_discriminating_py.py"
assert_exit "--file --check exits 0 on a clean test file" 0 "$rc"
run_file --file "$FIX/negative/test_discriminating_py.py" --count
assert_exit "--file --count completes" 0 "$rc"
assert_matches "--file --count prints 0" "$out" '^0$'
run_file --check --file "$SCRIPT_DIR/cant-fail-scan.sh"
assert_exit "--file on a file no ecosystem claims fails closed (exit 2)" 2 "$rc"
assert_contains "--file on an unclaimed file reports 0 examined" "$out" "0 test files were examined"
run_file --file "$TMP_ROOT/no-such.test.js"
assert_exit "--file on a missing path refuses (exit 2)" 2 "$rc"
run_file --file
assert_exit "--file without a value refuses (exit 2)" 2 "$rc"

# --lines: report only findings whose test block overlaps the named lines, so an
# edit hook stays quiet on blocks the edit never touched (hook-precision rule 1).
run_file --file "$FIX/positive/cant-fail-js.test.js" --lines 12
assert_contains "--lines keeps the finding of the block it touches" "$out" "cant-fail-js.test.js:11: test 'adds numbers'"
assert_not_contains "--lines drops a finding in an untouched block" "$out" "cant-fail-js.test.js:8:"
run_file --file "$FIX/positive/cant-fail-js.test.js" --lines 7
assert_contains "--lines keeps a line-scoped finding when its block is touched elsewhere" "$out" "cant-fail-js.test.js:8:"
assert_not_contains "--lines keeps only that block" "$out" "cant-fail-js.test.js:11:"
run_file --file "$FIX/positive/cant-fail-js.test.js" --lines 3,25-26 --count
assert_matches "--lines takes a list of lines and ranges" "$out" '^1$'
run_file --file "$FIX/positive/cant-fail-js.test.js" --lines 1-4 --count
assert_matches "--lines outside every block reports nothing" "$out" '^0$'
printf '%s\n' "import { test, expect } from 'vitest';" "" "test('adds', () => {" \
  "  sum(1, 2);" "  expect(sum(1, 2)).toBe(sum(1, 2)); });" >"$TMP_ROOT/closing.test.ts"
run_file --file "$TMP_ROOT/closing.test.ts" --lines 4 --count
assert_matches "--lines keeps a finding on the block's closing line" "$out" '^1$'
printf '%s\n' "public class T {" "  [Fact]" "  public void Adds()" "    => Assert.Equal(Sum(1, 2), Sum(1, 2));" "}" \
  >"$TMP_ROOT/ClosingTests.cs"
run_file --file "$TMP_ROOT/ClosingTests.cs" --lines 3 --count
assert_matches "--lines keeps a C# expression body's finding when the signature line is touched" "$out" '^1$'
printf '%s\n' "def test_a():" "    foo()" "" "def test_b():" "    assert foo() == 1" >"$TMP_ROOT/test_ranges.py"
run_file --file "$TMP_ROOT/test_ranges.py" --lines 4 --count
assert_matches "--lines does not stretch a Python block onto the next def" "$out" '^0$'
run_file --file "$TMP_ROOT/test_ranges.py" --lines 2 --count
assert_matches "--lines reports the Python block it touches" "$out" '^1$'
run_file --lines 12
assert_exit "--lines without --file refuses (exit 2)" 2 "$rc"
run_file --file "$FIX/positive/cant-fail-js.test.js" --lines 12x
assert_exit "--lines with a malformed list refuses (exit 2)" 2 "$rc"

# --blocks: one `block <file>:<start>-<end> <ordinal> <name>` line per examined
# test block in scope, in every adapter family. The ordinal counts same-named
# blocks through the whole file, so a --lines run numbers a block the way an
# unscoped run does. Expected ranges are read off the fixture text by hand.
B="$TMP_ROOT/blocks"
mkdir -p "$B"
printf '%s\n' "import { test, expect } from 'vitest';" "" \
  "test('adds', () => {" "  expect(sum(1, 2)).toBe(3);" "});" \
  "test('adds', () => {" "  expect(sum(2, 2)).toBe(4);" "});" \
  "test('subs', () => {" "  expect(sub(3, 2)).toBe(1);" "});" >"$B/dup.test.ts"
run_file --file "$B/dup.test.ts" --blocks
assert_exit "--blocks completes (exit 0)" 0 "$rc"
assert_contains "--blocks keeps the report of a clean file" "$out" "No can't-fail tests found."
assert_matches "--blocks: JS first 'adds' is ordinal 1" "$out" '^block dup\.test\.ts:3-5 1 adds$'
assert_matches "--blocks: JS second 'adds' is ordinal 2" "$out" '^block dup\.test\.ts:6-8 2 adds$'
assert_matches "--blocks: JS 'subs' is ordinal 1" "$out" '^block dup\.test\.ts:9-11 1 subs$'
run_file --file "$B/dup.test.ts" --blocks --lines 7
assert_matches "--blocks --lines keeps the whole-file ordinal" "$out" '^block dup\.test\.ts:6-8 2 adds$'
if [[ "$(count_lines "$out" '^block ')" == 1 ]]; then pass "--blocks --lines lists only the touched block"; else fail "--blocks --lines lists only the touched block" "$out"; fi
run_file --file "$B/dup.test.ts"
assert_not_contains "no --blocks, no block lines" "$out" "block dup"
run_file --file "$FIX/positive/cant-fail-js.test.js" --blocks
assert_contains "--blocks keeps the findings" "$out" "cant-fail-js.test.js:11: test 'adds numbers'"
assert_matches "--blocks lists blocks beside findings" "$out" '^block plugins/testing/skills/audit/evals/fixtures/positive/cant-fail-js\.test\.js:11-13 1 adds numbers$'
run_file --file "$B/dup.test.ts" --blocks --check
assert_exit "--blocks works only in the report mode (exit 2)" 2 "$rc"
assert_contains "--blocks outside the report mode says so" "$out" "--blocks lists blocks in the report mode only"

printf '%s\n' "public class T {" "  [Fact]" "  public void Adds()" "  {" "    Assert.Equal(3, Sum(1, 2));" "  }" \
  "  [Fact]" "  public void Subs()" "    => Assert.Equal(1, Sub(3, 2));" "}" >"$B/BlocksTests.cs"
run_file --file "$B/BlocksTests.cs" --blocks
assert_matches "--blocks: C# brace body" "$out" '^block BlocksTests\.cs:3-6 1 Adds$'
assert_matches "--blocks: C# => body" "$out" '^block BlocksTests\.cs:8-9 1 Subs$'

# A Python block ends on its last code line: the blank line before the next
# def is not part of it.
printf '%s\n' "def test_a():" "    assert foo() == 1" "" "def test_b():" "    assert foo() == 2" >"$B/test_blocks.py"
run_file --file "$B/test_blocks.py" --blocks
assert_matches "--blocks: Python block ends on its last code line" "$out" '^block test_blocks\.py:1-2 1 test_a$'
assert_matches "--blocks: Python last block" "$out" '^block test_blocks\.py:4-5 1 test_b$'
run_file --file "$B/test_blocks.py" --blocks --lines 3
assert_not_contains "--blocks: a blank line between defs touches no block" "$out" "block test_blocks"

printf '%s\n' "#!/usr/bin/env bats" "" '@test "greets" {' "  run greet" '  [ "$status" -eq 0 ]' "}" "" \
  '@test "greets" {' "  run greet x" '  [ "$output" = "hi x" ]' "}" >"$B/greet.bats"
run_file --file "$B/greet.bats" --blocks
assert_matches "--blocks: bats first @test" "$out" '^block greet\.bats:3-6 1 greets$'
assert_matches "--blocks: bats second @test of one name" "$out" '^block greet\.bats:8-11 2 greets$'

printf '%s\n' "Describe 'Sum' {" "  It 'adds' {" "    Sum 1 2 | Should -Be 3" "  }" "}" >"$B/Sum.Tests.ps1"
run_file --file "$B/Sum.Tests.ps1" --blocks
assert_matches "--blocks: Pester It" "$out" '^block Sum\.Tests\.ps1:2-4 1 adds$'

printf '%s\n' "package sum" "" 'import "testing"' "" "func TestSum(t *testing.T) {" \
  "	if Sum(1, 2) != 3 {" '		t.Fatal("want 3")' "	}" "}" >"$B/sum_test.go"
run_file --file "$B/sum_test.go" --blocks
assert_matches "--blocks: Go test func" "$out" '^block sum_test\.go:5-9 1 TestSum$'

printf '%s\n' "#!/usr/bin/env bash" "source ./lib.sh" 'assert_eq "$(greet)" hi' "pass done" >"$B/greet.test.sh"
run_file --file "$B/greet.test.sh" --blocks --lines 3
assert_matches "--blocks: a bash harness is one whole-file block" "$out" '^block greet\.test\.sh:1-4 1 greet\.test\.sh$'

# --inventory: per-line counts of test starts, assertion tokens and skip
# markers, and the literal side of each equality, for texts judged with the
# adapter and config of the --file path (the test-weaken hook's two sides).
printf '%s\n' "import { test, expect } from 'vitest';" "test('adds', () => {" "  expect(sum(1, 2)).toBe(3);" \
  "  // expect(gone()).toBe(1);" "});" "test.skip('later', () => {});" >"$TMP_ROOT/inv.test.ts"
printf '%s\n' "  expect(sum(1, 2)).toBe(3);" "  assert.equal(f(x), 'a b');" >"$TMP_ROOT/inv-frag.txt"
run_file --file "$TMP_ROOT/inv.test.ts" --inventory "$TMP_ROOT/inv.test.ts" --inventory "$TMP_ROOT/inv-frag.txt"
assert_exit "--inventory completes (exit 0)" 0 "$rc"
assert_matches "--inventory counts a test start" "$out" $'^1\ttest\t1\ttest\\(.adds'
assert_matches "--inventory counts an assertion token" "$out" $'^1\tassertion\t1\texpect\\(sum\\(1, 2\\)\\)\\.toBe\\(3\\);$'
assert_not_contains "--inventory ignores a commented-out assertion" "$out" "gone()"
assert_matches "--inventory counts a skip marker" "$out" $'^1\tskip\t1\ttest\\.skip'
assert_matches "--inventory reads the second text under its own index" "$out" $'^2\tassertion\t1\texpect'
assert_matches "--inventory gives an equality's actual and literal sides" "$out" $'^2\texpect\tsum\\(1,2\\)\t3$'
assert_matches "--inventory reads a call2 equality" "$out" $'^2\texpect\tf\\(x\\)\t\'ab\'$'
assert_not_contains "--inventory prints no finding or block record" "$out" $'B\t'
printf '%s\n' "const s = \`abc" "  expect(a).toBe(1);" >"$TMP_ROOT/inv-open.txt"
run_file --file "$TMP_ROOT/inv.test.ts" --inventory "$TMP_ROOT/inv-open.txt"
assert_matches "--inventory marks a text the lexer ends inside" "$out" $'^1\tunjudged$'
run_file --inventory "$TMP_ROOT/inv.test.ts"
assert_exit "--inventory without --file refuses (exit 2)" 2 "$rc"
run_file --file "$SCRIPT_DIR/cant-fail-scan.sh" --inventory "$TMP_ROOT/inv.test.ts"
assert_exit "--inventory on a file no adapter claims completes (exit 0)" 0 "$rc"
assert_not_contains "--inventory on an unclaimed file prints no inventory" "$out" $'1\t'

# --- adapter-load.awk: the YAML-subset adapter loader --------------------------
# Driven through awk directly. Output is one `id<TAB>key<TAB>value` record per
# scalar and per list item; anything outside the subset exits 2 naming the file
# and line. The shipped adapters are js-jest.yaml, js-vitest.yaml,
# py-pytest.yaml and cs-xunit.yaml. When an engine change must not move a
# finding, run parity-check.sh beside this suite: it diffs the scanner at a
# base ref against the working tree under gawk and mawk.
LOAD="$SCRIPT_DIR/adapter-load.awk"
ADIR="$TMP_ROOT/adapters"
mkdir -p "$ADIR"
# load_yaml <file-name> <content>: write the adapter, load it alone, leaving
# stdout in $out, stderr in $err and the exit code in $rc.
load_yaml() {
  printf '%s' "$2" >"$ADIR/$1"
  rc=0
  out="$(awk -f "$LOAD" "$ADIR/$1" 2>"$TMP_ROOT/load.err")" || rc=$?
  err="$(cat "$TMP_ROOT/load.err")"
}
TAB=$'\t'
load_yaml good.yaml $'# comment line\r\nid: demo\r\nlanguage: js\nblock_model: brace  # trailing comment\nfiles: [\'*.test.js\', \'*.spec.js\']\ntest_start: [x]\ndetect:\n  any_regex:\n    - \'from [\'\'"]vitest\'\n  # nested comment\nassertion.calls:\n- \'expect[[:space:]]*\\(\'\nmock:\n  create: [\'vi\\.fn\']\n  verify:\n    - toHaveBeenCalled\nsuppress_marker: \'cant-fail-ok:\'\n'
assert_exit "loader accepts the subset (exit 0)" 0 "$rc"
assert_contains "loader emits a scalar, CR stripped, comment dropped" "$out" "demo${TAB}block_model${TAB}brace"
assert_contains "loader emits each flow-list item" "$out" "demo${TAB}files${TAB}*.spec.js"
assert_contains "loader nests block maps into dotted keys and unescapes ''" "$out" "demo${TAB}detect.any_regex${TAB}from ['\"]vitest"
assert_contains "loader accepts a dotted key and a same-indent list item" "$out" "demo${TAB}assertion.calls${TAB}expect[[:space:]]*\\("
assert_contains "loader closes a nested map key at a sibling" "$out" "demo${TAB}mock.verify${TAB}toHaveBeenCalled"
assert_contains "loader keeps a quoted colon" "$out" "demo${TAB}suppress_marker${TAB}cant-fail-ok:"
load_yaml dq.yaml $'id: dq\nlanguage: js\nfiles:\n  - "*.test.js"\n'
assert_exit "loader rejects a double-quoted scalar (exit 2)" 2 "$rc"
assert_contains "loader names the file and line of the rejection" "$err" "dq.yaml:4:"
load_yaml ws.yaml $'id: ws\nlanguage: js\ntest_start:\n  - \'it\\s*\\(\'\n' # portability-ok: deliberately non-portable regex the loader must reject
assert_exit "loader rejects a GNU class escape in a regex (exit 2)" 2 "$rc"
assert_contains "loader names the non-portable regex line" "$err" "ws.yaml:4:"
assert_contains "loader says why a GNU class escape is refused" "$err" "non-portable regex escape"
load_yaml iv.yaml $'id: iv\nlanguage: js\ntest_start: [\'a{2}\']\n'
assert_exit "loader rejects an interval in a regex (exit 2)" 2 "$rc"
assert_contains "loader says why an interval is refused" "$err" "interval"
load_yaml br.yaml $'id: br\nlanguage: js\ntest_start: [\'(a)\\1\']\n'
assert_exit "loader rejects a backreference in a regex (exit 2)" 2 "$rc"
assert_contains "loader says why a backreference is refused" "$err" "non-portable regex escape \\1"
load_yaml uk.yaml $'id: uk\nlanguage: js\ntest_starts: [x]\n'
assert_exit "loader rejects an unknown key (exit 2)" 2 "$rc"
assert_contains "loader names the unknown key" "$err" "uk.yaml:3: unknown key: test_starts"
load_yaml fm.yaml $'id: fm\nlanguage: js\ntest_start:\n  - {a: b}\n'
assert_exit "loader rejects a flow map (exit 2)" 2 "$rc"
assert_contains "loader says a flow map is unsupported" "$err" "fm.yaml:4: unsupported YAML syntax"
load_yaml an.yaml $'id: &a an\nlanguage: js\n'
assert_exit "loader rejects an anchor (exit 2)" 2 "$rc"
assert_contains "loader says an anchor is unsupported" "$err" "an.yaml:1: unsupported YAML syntax"
load_yaml ty.yaml $'id: ty\nlanguage: js\nfiles: x\n'
assert_exit "loader rejects a scalar where a list belongs (exit 2)" 2 "$rc"
assert_contains "loader says files takes a list" "$err" "files takes a list"
load_yaml nl.yaml $'id: nl\nlanguage: cobol\n'
assert_exit "loader rejects an unknown language (exit 2)" 2 "$rc"
assert_contains "loader names the bad language" "$err" "got: cobol"
load_yaml noid.yaml $'language: js\n'
assert_exit "loader rejects an adapter without an id (exit 2)" 2 "$rc"
assert_contains "loader says the id is missing" "$err" "noid.yaml: no id"
printf 'id: base\nlanguage: js\nfiles: [a]\ntest_start: [b]\n' >"$ADIR/base.yaml"
printf 'id: child\nextends: base\ntest_start: [c]\n' >"$ADIR/child.yaml"
rc=0
out="$(awk -f "$LOAD" "$ADIR/child.yaml" "$ADIR/base.yaml" 2>&1)" || rc=$?
assert_exit "loader resolves extends across files (exit 0)" 0 "$rc"
assert_contains "extends inherits a field the child omits" "$out" "child${TAB}files${TAB}a"
assert_contains "extends keeps the child's own field" "$out" "child${TAB}test_start${TAB}c"
assert_not_contains "extends does not merge a field the child sets" "$out" "child${TAB}test_start${TAB}b"
assert_matches "load order is argument order" "$(printf '%s\n' "$out" | head -1)" "^child${TAB}"
printf 'id: orphan\nextends: nobody\nlanguage: js\n' >"$ADIR/orphan.yaml"
rc=0
out="$(awk -f "$LOAD" "$ADIR/orphan.yaml" 2>&1)" || rc=$?
assert_exit "loader rejects extends of an unknown adapter (exit 2)" 2 "$rc"
assert_contains "loader names the unknown parent" "$out" "extends unknown adapter: nobody"
rc=0
out="$(awk -f "$LOAD" "$ADIR/base.yaml" "$ADIR/base.yaml" 2>&1)" || rc=$?
assert_exit "loader rejects a duplicate adapter id (exit 2)" 2 "$rc"
assert_contains "loader names the duplicate id" "$out" "duplicate adapter id: base"
rc=0
out="$(awk -f "$LOAD" "$SCRIPT_DIR"/../adapters/*.yaml 2>&1)" || rc=$?
assert_exit "every shipped adapter loads (exit 0)" 0 "$rc"
# Named by file so affected-tests.sh maps each adapter to this suite.
for f in bash-bats.yaml bash-harness.yaml cs-mstest.yaml cs-nunit.yaml cs-xunit.yaml go-testing.yaml \
  js-jest.yaml js-node-test.yaml js-playwright.yaml js-vitest.yaml pwsh-pester.yaml py-pytest.yaml py-unittest.yaml; do
  id="${f%.yaml}"
  assert_contains "shipped adapter $id loads" "$out" "$id${TAB}language${TAB}"
done
load_yaml rs.yaml $'id: rs\nlanguage: js\nadditional_test_blocks: [x]\n'
assert_exit "loader rejects a reserved, unimplemented field (exit 2)" 2 "$rc"
assert_contains "loader says the field is reserved" "$err" "additional_test_blocks is reserved"
load_yaml nt.yaml $'id: nt\nlanguage: js\nfiles: [a]\n'
assert_exit "loader rejects an adapter that claims files with no test_start (exit 2)" 2 "$rc"
assert_contains "loader says test_start is missing" "$err" "nt.yaml: claims files but has no test_start"
printf 'id: empty\nextends: base\ntest_start: []\n' >"$ADIR/empty.yaml"
rc=0
out="$(awk -f "$LOAD" "$ADIR/empty.yaml" "$ADIR/base.yaml" 2>&1)" || rc=$?
assert_exit "loader rejects an empty test_start overriding an inherited one (exit 2)" 2 "$rc"
assert_contains "loader names the adapter left without a matcher" "$out" "empty.yaml: claims files but has no test_start"
load_yaml fm.yaml $'id: fm\nlanguage: js\nblock_model: file\n'
assert_exit "loader rejects the file model outside bash (exit 2)" 2 "$rc"
assert_contains "loader names the unsupported model" "$err" "block_model file is not supported for language js"
load_yaml ad.yaml $'id: ad\nlanguage: bash\nadvisory: yes\n'
assert_exit "loader rejects an advisory value other than true or false (exit 2)" 2 "$rc"
assert_contains "loader states the advisory values" "$err" "advisory is true or false"
load_yaml rf.yaml $'id: rf\nlanguage: js\nrules_off: [flaky-passes-suite]\n'
assert_exit "loader rejects a rules_off slug no test adapter can turn off (exit 2)" 2 "$rc"
assert_contains "loader says rules_off takes test-body rule slugs" "$err" "test-body rule slugs"
load_yaml rv.yaml $'id: rv\nlanguage: js\nequality.receiver: [toBe]\n'
assert_exit "loader rejects a receiver entry without a wrapper (exit 2)" 2 "$rc"
assert_contains "loader states the receiver form" "$err" "<wrapper>.<matcher>"
load_yaml oi.yaml $'id: oi\n  language: js\n'
assert_exit "loader rejects a key indented under a scalar (exit 2)" 2 "$rc"
assert_contains "loader names the misindented key" "$err" "oi.yaml:2: bad indentation"
load_yaml si.yaml $'id: si\nlanguage: js\nmock:\n  create: [x]\n    verify: [y]\n'
assert_exit "loader rejects a sibling key at a deeper indent (exit 2)" 2 "$rc"
assert_contains "loader names the uneven sibling" "$err" "si.yaml:5: bad indentation"
load_yaml dm.yaml $'---\nid: dm\n'
assert_exit "loader rejects a document marker (exit 2)" 2 "$rc"
assert_contains "loader says document markers are unsupported" "$err" "dm.yaml:1: document markers"

# --- adapter precedence: two adapters claim *.test.ts ------------------------
# js-jest and js-vitest share every glob. The one whose detect.any_regex matches
# the file wins; with no match the first in load order (js-jest) does.
PREC="$TMP_ROOT/prec"
mkdir -p "$PREC"
printf "import { it, expect } from 'vitest'\nit('a', () => { expect(1).toBe(1) })\n" >"$PREC/vi.test.ts"
printf "const f = jest.fn()\nit('a', () => { expect(f).toBe(f) })\n" >"$PREC/je.test.ts"
printf "it('a', () => { expect(1).toBe(1) })\n" >"$PREC/plain.test.ts"
run_file --file "$PREC/vi.test.ts"
assert_contains "a vitest import selects js-vitest" "$out" "adapter: js-vitest"
run_file --file "$PREC/je.test.ts"
assert_contains "jest.fn selects js-jest" "$out" "adapter: js-jest"
printf "import { vi } from 'vitest'\nconst f = jest.fn()\nit('a', () => { expect(f).toBe(f) })\n" >"$PREC/both.test.ts"
run_file --file "$PREC/both.test.ts"
assert_contains "when both detect, the first in load order wins" "$out" "adapter: js-jest"
run_file --file "$PREC/plain.test.ts"
assert_contains "no detect match falls back to the first adapter in load order" "$out" "adapter: js-jest"
run_file --file "$SCRIPT_DIR/cant-fail-scan.sh"
assert_contains "an unclaimed file names no adapter" "$out" "adapter: none"
# cs-mstest and cs-nunit sort before cs-xunit but carry detect lists; a C# file
# none of them detects falls to the claimant with no detect list.
printf 'public class ATests\n{\n    [Fact]\n    public void A()\n    {\n        Assert.True(true);\n    }\n}\n' >"$PREC/ATests.cs"
run_file --file "$PREC/ATests.cs"
assert_contains "no detect match prefers the claimant with no detect list" "$out" "adapter: cs-xunit"

# --- bash lexer: the masker keeps sync, or the file reports nothing -----------
# A desynced masker hides every later assertion, which under the file model is
# a false zero-assertion; each case would fire if the masker got it wrong.
SH="$TMP_ROOT/sh"
mkdir -p "$SH"
printf 'cat <<EOF\npass is only text here\nEOF\necho done\n' >"$SH/heredoc.test.sh"
run_file --file "$SH/heredoc.test.sh"
assert_finding_count "a heredoc body is text, not an assertion" 1
printf 'cat <<-'"'"'EOF'"'"'\n\tpass is only text here\n\tEOF\necho done\n' >"$SH/heredoc-dash.test.sh"
run_file --file "$SH/heredoc-dash.test.sh"
assert_finding_count "a quoted <<- heredoc ends at its tab-indented terminator" 1
printf '[ $# -eq 0 ] || fail "takes no arguments"\n' >"$SH/argc.test.sh"
run_file --file "$SH/argc.test.sh"
assert_finding_count "\$# is not a comment" 0
printf 'x=$(cat <<<'"'"'not json'"'"')\npass "after the here-string"\n' >"$SH/herestring.test.sh"
run_file --file "$SH/herestring.test.sh"
assert_contains "a here-string does not open a heredoc" "$out" "test blocks parsed: 1;"
printf '[[ ${#x[@]} -eq 1 ]] || fail "count"\n' >"$SH/length.test.sh"
run_file --file "$SH/length.test.sh"
assert_finding_count "\${#x} is not a comment" 0
printf 'v="$(echo "it'"'"'s")"\npass "after the substitution"\n' >"$SH/subst.test.sh"
run_file --file "$SH/subst.test.sh"
assert_contains "quotes nest inside \$( ) inside a double-quoted string" "$out" "test blocks parsed: 1;"
assert_finding_count "a nested quote does not hide a later assertion" 0
printf 'gate_test::run_suite "$DIR" test_x.py\n' >"$SH/gate.test.sh"
run_file --file "$SH/gate.test.sh"
assert_finding_count "gate_test::run_suite delegates the assertions" 0
printf 'exec node "$DIR/x.test.mjs"\n' >"$SH/exec.test.sh"
run_file --file "$SH/exec.test.sh"
assert_finding_count "exec running a suite file delegates the assertions" 0
printf 'echo "never closed\necho done\n' >"$SH/open.test.sh"
run_file --file "$SH/open.test.sh"
assert_finding_count "a string still open at end of file reports nothing" 0
assert_contains "the coverage block counts a file whose lexer lost sync" "$out" "files whose lexer lost sync (not judged): 1"
printf 'echo done\n' >"$SH/none.test.sh"
run_file --file "$SH/none.test.sh"
assert_finding_count "a harness with no assertion reports zero-assertion" 1
run_file --file "$SH/none.test.sh" --check
assert_exit "bash-harness findings are advisory in --check" 0 "$rc"
assert_contains "the advisory note counts the advisory adapter" "$out" "advisory adapters (bash-bats, bash-harness) 1."
run_file --file "$SH/none.test.sh" --check --strict
assert_exit "--strict gates bash-harness findings" 1 "$rc"

# --- corpus: one test per file, exact rule sets --------------------------------
# Each file is stored as <real name>.fixture so no test runner, linter or
# enumerator treats a planted defect as a real suite; the loop scans a copy
# under the real name. A bad file's `expect: <rule-id>` lines are the exact
# rule set --file must report; a good file must report none. The adapter
# that claims the copy must be the one its directory names.
CORPUS="$FIX/corpus"
corpus_files=(
  bash-bats/bad/bats-greet-against-itself.bats.fixture
  bash-bats/bad/bats-greet-prints-only.bats.fixture
  bash-bats/bad/bats-greet-run-unchecked.bats.fixture
  bash-bats/bad/bats-last-bang-or-true.bats.fixture
  bash-bats/bad/bats-page-source-text.bats.fixture
  bash-bats/bad/bats-retry-limit-restated.bats.fixture
  bash-bats/good/bats-config-removed-last-bang.bats.fixture
  bash-bats/good/bats-greet-against-literal.bats.fixture
  bash-bats/good/bats-greet-asserts-output.bats.fixture
  bash-bats/good/bats-greet-run-status.bats.fixture
  bash-bats/good/bats-greet-skipped.bats.fixture
  bash-bats/good/bats-greet-test-command.bats.fixture
  bash-bats/good/bats-init-writes-config.bats.fixture
  bash-bats/good/bats-parsed-args-count.bats.fixture
  bash-bats/good/bats-repaired-oracles.bats.fixture
  bash-harness/bad/bracket-status-dropped.test.sh.fixture
  bash-harness/bad/deploy-source-text.test.sh.fixture
  bash-harness/bad/prints-only.test.sh.fixture
  bash-harness/bad/retry-limit-restated.test.sh.fixture
  bash-harness/bad/sort-against-itself.test.sh.fixture
  bash-harness/good/fail-and-exit.test.sh.fixture
  bash-harness/good/failure-counter-arith-exit.test.sh.fixture
  bash-harness/good/failure-counter.test.sh.fixture
  bash-harness/good/node-driver-heredoc.test.sh.fixture
  bash-harness/good/pwsh-selftest.test.sh.fixture
  bash-harness/good/python-in-variable.test.sh.fixture
  bash-harness/good/repaired-oracles.test.sh.fixture
  bash-harness/good/sort-against-literal.test.sh.fixture
  bash-harness/good/sources-test-harness.test.sh.fixture
  cs-mstest/bad/OrderAlwaysTrueTests.cs.fixture
  cs-mstest/bad/OrderDiscountIfTests.cs.fixture
  cs-mstest/bad/OrderIsNotNullTests.cs.fixture
  cs-mstest/bad/OrderLinesSumTests.cs.fixture
  cs-mstest/bad/OrderPlacementTests.cs.fixture
  cs-mstest/bad/OrderReceiptVerifyTests.cs.fixture
  cs-mstest/bad/OrderSourceTextTests.cs.fixture
  cs-mstest/bad/OrderTotalFormatTests.cs.fixture
  cs-mstest/good/OrderArchiveIgnoredClassTests.cs.fixture
  cs-mstest/good/OrderParseExpectedExceptionTests.cs.fixture
  cs-mstest/good/OrderPlacementAssertedTests.cs.fixture
  cs-mstest/good/OrderRepaired4bTests.cs.fixture
  cs-mstest/good/OrderRepairedOraclesTests.cs.fixture
  cs-mstest/good/OrderSyncIgnoredTests.cs.fixture
  cs-mstest/good/OrderTotalFormatLiteralTests.cs.fixture
  cs-nunit/bad/CartCheckoutThatAsyncTests.cs.fixture
  cs-nunit/bad/CartDiscountTests.cs.fixture
  cs-nunit/bad/CartIsNotNullTests.cs.fixture
  cs-nunit/bad/CartPlaceOrderCatchTests.cs.fixture
  cs-nunit/bad/CartPurchaseTests.cs.fixture
  cs-nunit/bad/CartReceiptVerifyTests.cs.fixture
  cs-nunit/bad/CartRefundTests.cs.fixture
  cs-nunit/bad/CartSourceTextTests.cs.fixture
  cs-nunit/bad/CartTotalSumTests.cs.fixture
  cs-nunit/good/CartBenchmarkExplicitTests.cs.fixture
  cs-nunit/good/CartDiscountLiteralTests.cs.fixture
  cs-nunit/good/CartDivideExpectedResultTests.cs.fixture
  cs-nunit/good/CartExportIgnoredTests.cs.fixture
  cs-nunit/good/CartPurchaseAssertedTests.cs.fixture
  cs-nunit/good/CartRepaired4bTests.cs.fixture
  cs-nunit/good/CartRepairedOraclesTests.cs.fixture
  cs-nunit/good/CartSyncIgnoredFixtureTests.cs.fixture
  cs-xunit/bad/DiagnosticsCheckPrintsOnlyTests.cs.fixture
  cs-xunit/bad/InvoiceExpressionNotNullTests.cs.fixture
  cs-xunit/bad/InvoiceExpressionVerifyTests.cs.fixture
  cs-xunit/bad/InvoiceLinesLoopTests.cs.fixture
  cs-xunit/bad/InvoiceNotNullTests.cs.fixture
  cs-xunit/bad/InvoiceOneLineNotNullTests.cs.fixture
  cs-xunit/bad/InvoiceOneLineShouldTests.cs.fixture
  cs-xunit/bad/InvoiceOverloadedHelperTests.cs.fixture
  cs-xunit/bad/InvoiceRecursiveOverloadTests.cs.fixture
  cs-xunit/bad/InvoiceRenderSnapshotTests.cs.fixture
  cs-xunit/bad/InvoiceShouldAloneTests.cs.fixture
  cs-xunit/bad/InvoiceTaskNamedHelperTests.cs.fixture
  cs-xunit/bad/InvoiceTotalSumTests.cs.fixture
  cs-xunit/bad/InvoiceTotalTests.cs.fixture
  cs-xunit/bad/PageSourceTextTests.cs.fixture
  cs-xunit/bad/ParserAsyncExpressionThrowsTests.cs.fixture
  cs-xunit/bad/QuoteExpectedParameterTests.cs.fixture
  cs-xunit/bad/SlugifyTests.cs.fixture
  cs-xunit/bad/WorkerRunAsyncTests.cs.fixture
  cs-xunit/good/AnalyzerHarnessRunAsyncTests.cs.fixture
  cs-xunit/good/DiagnosticsCheckAssertsTests.cs.fixture
  cs-xunit/good/HttpStatusFieldTests.cs.fixture
  cs-xunit/good/InvoiceMailerTests.cs.fixture
  cs-xunit/good/InvoiceOneLineOraclesTests.cs.fixture
  cs-xunit/good/InvoiceOverloadDelegatesTests.cs.fixture
  cs-xunit/good/InvoicePendingTests.cs.fixture
  cs-xunit/good/InvoiceRepaired4bTests.cs.fixture
  cs-xunit/good/InvoiceRepairedOraclesTests.cs.fixture
  cs-xunit/good/InvoiceTotalFluentTests.cs.fixture
  cs-xunit/good/InvoiceTotalShouldlyTests.cs.fixture
  cs-xunit/good/InvoiceVerifyHelperTests.cs.fixture
  cs-xunit/good/OrderPricedHelperTests.cs.fixture
  cs-xunit/good/SameFileAssertingHelperTests.cs.fixture
  cs-xunit/good/SlugifyLiteralTests.cs.fixture
  go-testing/bad/go_add_deepequal_derived_test.go.fixture
  go-testing/bad/go_handler_source_text_test.go.fixture
  go-testing/bad/go_query_diff_itself_test.go.fixture
  go-testing/bad/go_render_snapshot_test.go.fixture
  go-testing/bad/go_rows_loop_unchecked_test.go.fixture
  go-testing/bad/go_slugify_logs_mismatch_test.go.fixture
  go-testing/bad/go_slugify_runs_test.go.fixture
  go-testing/bad/go_user_nil_check_test.go.fixture
  go-testing/good/go_cart_helper_test.go.fixture
  go-testing/good/go_codec_fuzz_test.go.fixture
  go-testing/good/go_export_skipped_test.go.fixture
  go-testing/good/go_hash_bench_test.go.fixture
  go-testing/good/go_log_branches_test.go.fixture
  go-testing/good/go_query_diff_literal_test.go.fixture
  go-testing/good/go_repaired_4b_test.go.fixture
  go-testing/good/go_repaired_oracles_test.go.fixture
  go-testing/good/go_slugify_checked_test.go.fixture
  js-jest/bad/jest-cart-total-reduce.test.ts.fixture
  js-jest/bad/jest-checkout-calls-payment-verbatim.test.ts.fixture
  js-jest/bad/jest-checkout-calls-payment.test.ts.fixture
  js-jest/bad/jest-checkout-source-text.test.ts.fixture
  js-jest/bad/jest-create-user-defined-verbatim.test.ts.fixture
  js-jest/bad/jest-discount-runs.test.ts.fixture
  js-jest/bad/jest-parse-error-in-catch.test.ts.fixture
  js-jest/bad/jest-receipt-snapshot.test.ts.fixture
  js-jest/bad/jest-slug-itself.test.js.fixture
  js-jest/bad/jest-split-call-runs.test.ts.fixture
  js-jest/bad/jest-sync-call-count.test.ts.fixture
  js-jest/bad/jest-upload-limit-restated.test.ts.fixture
  js-jest/bad/jest-user-resolves-unawaited.test.ts.fixture
  js-jest/good/jest-codemod-testfixtures.test.ts.fixture
  js-jest/good/jest-discount-checked.test.ts.fixture
  js-jest/good/jest-repaired-4b.test.ts.fixture
  js-jest/good/jest-repaired-oracles.test.ts.fixture
  js-jest/good/jest-slug-literal.test.js.fixture
  js-jest/good/jest-split-call.test.ts.fixture
  js-node-test/bad/node-test-config-rejects-unawaited.test.mjs.fixture
  js-node-test/bad/node-test-context-assert.test.mjs.fixture
  js-node-test/bad/node-test-csv-itself.test.mjs.fixture
  js-node-test/bad/node-test-page-source-text.test.mjs.fixture
  js-node-test/bad/node-test-parse-throws-any.test.mjs.fixture
  js-node-test/bad/node-test-post-limit-restated.test.mjs.fixture
  js-node-test/bad/node-test-price-runs.test.mjs.fixture
  js-node-test/bad/node-test-rows-foreach-unchecked.test.mjs.fixture
  js-node-test/bad/node-test-total-reduce.test.mjs.fixture
  js-node-test/good/node-test-context-skip.test.mjs.fixture
  js-node-test/good/node-test-csv-literal.test.mjs.fixture
  js-node-test/good/node-test-destructured.test.js.fixture
  js-node-test/good/node-test-helper-asserts.test.cjs.fixture
  js-node-test/good/node-test-price-checked.test.mjs.fixture
  js-node-test/good/node-test-repaired-4b.test.mjs.fixture
  js-node-test/good/node-test-repaired-oracles.test.mjs.fixture
  js-node-test/good/node-test-suite-skip.test.mjs.fixture
  js-node-test/good/node-test-todo-option.test.mjs.fixture
  js-node-test/good/node-test-userscript-vm.test.mjs.fixture
  js-playwright/bad/playwright-banner-if-visible.spec.ts.fixture
  js-playwright/bad/playwright-login-clicks.spec.ts.fixture
  js-playwright/bad/playwright-nav-aria-snapshot.spec.ts.fixture
  js-playwright/bad/playwright-page-size-restated.spec.ts.fixture
  js-playwright/bad/playwright-page-source-text.spec.ts.fixture
  js-playwright/bad/playwright-saved-unawaited.spec.ts.fixture
  js-playwright/bad/playwright-title-itself.spec.ts.fixture
  js-playwright/bad/playwright-token-truthy.spec.ts.fixture
  js-playwright/good/playwright-body-skip.spec.ts.fixture
  js-playwright/good/playwright-configured-expect.spec.ts.fixture
  js-playwright/good/playwright-describe-fixme.spec.ts.fixture
  js-playwright/good/playwright-login-asserted.spec.ts.fixture
  js-playwright/good/playwright-poll.spec.ts.fixture
  js-playwright/good/playwright-repaired-4b.spec.ts.fixture
  js-playwright/good/playwright-repaired-oracles.spec.ts.fixture
  js-playwright/good/playwright-soft-step.spec.ts.fixture
  js-playwright/good/playwright-title-literal.spec.ts.fixture
  js-vitest/bad/vitest-add-recomputed.test.ts.fixture
  js-vitest/bad/vitest-cart-runs.test.ts.fixture
  js-vitest/bad/vitest-duration-itself.test.ts.fixture
  js-vitest/bad/vitest-helper-chain-silent.test.ts.fixture
  js-vitest/bad/vitest-invoice-inline-snapshot.test.ts.fixture
  js-vitest/bad/vitest-limit-against-itself.test.ts.fixture
  js-vitest/bad/vitest-loop-over-empty-mapped-literal.test.ts.fixture
  js-vitest/bad/vitest-order-total-recomputed.test.ts.fixture
  js-vitest/bad/vitest-pitch-detail-source-order.test.ts.fixture
  js-vitest/bad/vitest-post-limit-restated.test.ts.fixture
  js-vitest/bad/vitest-queue-poll-unawaited.test.ts.fixture
  js-vitest/bad/vitest-rows-loop-unchecked.test.ts.fixture
  js-vitest/bad/vitest-session-truthy.test.ts.fixture
  js-vitest/bad/vitest-user-fixture-literal.test.ts.fixture
  js-vitest/good/vitest-cart-checked.test.ts.fixture
  js-vitest/good/vitest-duration-literal.test.ts.fixture
  js-vitest/good/vitest-generated-types-fresh.test.ts.fixture
  js-vitest/good/vitest-helper-chain-throws.test.ts.fixture
  js-vitest/good/vitest-length-invariant.test.ts.fixture
  js-vitest/good/vitest-loop-over-literal-probes.test.ts.fixture
  js-vitest/good/vitest-parsed-config-fields.test.ts.fixture
  js-vitest/good/vitest-poll-helper-rejects.test.ts.fixture
  js-vitest/good/vitest-repaired-4b.test.ts.fixture
  js-vitest/good/vitest-repaired-oracles.test.ts.fixture
  js-vitest/good/vitest-split-call-options.test.ts.fixture
  planted/bad/PlantedShouldAloneTests.cs.fixture
  planted/bad/PlantedSumRecomputedTests.cs.fixture
  planted/bad/PlantedUnawaitedAsyncTests.cs.fixture
  planted/bad/planted-constant-restatement.test.ts.fixture
  planted/bad/planted-no-assertion.test.ts.fixture
  planted/bad/planted-reduce-recomputed.test.ts.fixture
  planted/bad/planted-self-identity.test.ts.fixture
  planted/bad/planted-source-text.test.ts.fixture
  planted/bad/planted-unawaited-expect.spec.ts.fixture
  planted/bad/test_planted_constant.py.fixture
  planted/bad/test_planted_sum_recomputed.py.fixture
  planted/bad/test_planted_tuple_assert.py.fixture
  pwsh-pester/bad/pester-module-source-text.Tests.ps1.fixture
  pwsh-pester/bad/pester-report-invoke-only.Tests.ps1.fixture
  pwsh-pester/bad/pester-report-not-empty.Tests.ps1.fixture
  pwsh-pester/bad/pester-rows-foreach-unchecked.Tests.ps1.fixture
  pwsh-pester/bad/pester-sum-against-itself.Tests.ps1.fixture
  pwsh-pester/bad/pester-sum-bare-comparison.Tests.ps1.fixture
  pwsh-pester/bad/pester-sum-writes-host.Tests.ps1.fixture
  pwsh-pester/bad/pester-total-measure-derived.Tests.ps1.fixture
  pwsh-pester/good/pester-continued-comparison.Tests.ps1.fixture
  pwsh-pester/good/pester-exit-code.Tests.ps1.fixture
  pwsh-pester/good/pester-repaired-4b.Tests.ps1.fixture
  pwsh-pester/good/pester-repaired-oracles.Tests.ps1.fixture
  pwsh-pester/good/pester-report-invoke-and-value.Tests.ps1.fixture
  pwsh-pester/good/pester-sum-against-literal.Tests.ps1.fixture
  pwsh-pester/good/pester-sum-context-skip.Tests.ps1.fixture
  pwsh-pester/good/pester-sum-foreach-table.Tests.ps1.fixture
  pwsh-pester/good/pester-sum-it-skip.Tests.ps1.fixture
  pwsh-pester/good/pester-sum-set-itresult.Tests.ps1.fixture
  pwsh-pester/good/pester-sum-should-be.Tests.ps1.fixture
  py-pytest/bad/test_pytest_limit_restated.py.fixture
  py-pytest/bad/test_pytest_order_fixture_literal.py.fixture
  py-pytest/bad/test_pytest_parametrize_split_runs.py.fixture
  py-pytest/bad/test_pytest_price_recomputed.py.fixture
  py-pytest/bad/test_pytest_price_sum_recomputed.py.fixture
  py-pytest/bad/test_pytest_render_snapshot.py.fixture
  py-pytest/bad/test_pytest_rows_loop_unchecked.py.fixture
  py-pytest/bad/test_pytest_slugify_runs.py.fixture
  py-pytest/bad/test_pytest_split_signature_runs.py.fixture
  py-pytest/bad/test_pytest_total_tuple_assert.py.fixture
  py-pytest/bad/test_pytest_user_not_none.py.fixture
  py-pytest/bad/test_pytest_views_source_text.py.fixture
  py-pytest/good/test_pytest_ast_parse_source.py.fixture
  py-pytest/good/test_pytest_deterministic_report.py.fixture
  py-pytest/good/test_pytest_exec_tool_script.py.fixture
  py-pytest/good/test_pytest_helper_check_returncode.py.fixture
  py-pytest/good/test_pytest_length_invariant.py.fixture
  py-pytest/good/test_pytest_loaded_config_fields.py.fixture
  py-pytest/good/test_pytest_price_literal.py.fixture
  py-pytest/good/test_pytest_raises.py.fixture
  py-pytest/good/test_pytest_repaired_4b.py.fixture
  py-pytest/good/test_pytest_repaired_oracles.py.fixture
  py-pytest/good/test_pytest_skip_marker.py.fixture
  py-pytest/good/test_pytest_skipif_split.py.fixture
  py-pytest/good/test_pytest_skipped_class.py.fixture
  py-pytest/good/test_pytest_slugify.py.fixture
  py-pytest/good/test_pytest_snapshot_local.py.fixture
  py-pytest/good/test_pytest_split_signature.py.fixture
  py-pytest/good/test_pytest_try_fail.py.fixture
  py-pytest/good/test_pytest_unittest_mock.py.fixture
  py-unittest/bad/test_unittest_after_skipped_class.py.fixture
  py-unittest/bad/test_unittest_config_recomputed.py.fixture
  py-unittest/bad/test_unittest_deliver_awaits.py.fixture
  py-unittest/bad/test_unittest_limit_restated.py.fixture
  py-unittest/bad/test_unittest_notify_called_once_with.py.fixture
  py-unittest/bad/test_unittest_other_class_helper.py.fixture
  py-unittest/bad/test_unittest_parse_except_only.py.fixture
  py-unittest/bad/test_unittest_parse_raises_exception.py.fixture
  py-unittest/bad/test_unittest_render_snapshot.py.fixture
  py-unittest/bad/test_unittest_slugify_runs.py.fixture
  py-unittest/bad/test_unittest_total_recomputed.py.fixture
  py-unittest/bad/test_unittest_views_source_text.py.fixture
  py-unittest/good/test_unittest_config_literal.py.fixture
  py-unittest/good/test_unittest_deterministic_call.py.fixture
  py-unittest/good/test_unittest_raises.py.fixture
  py-unittest/good/test_unittest_repaired_4b.py.fixture
  py-unittest/good/test_unittest_repaired_oracles.py.fixture
  py-unittest/good/test_unittest_self_helper_asserts.py.fixture
  py-unittest/good/test_unittest_skipped_class.py.fixture
  py-unittest/good/test_unittest_skiptest.py.fixture
  py-unittest/good/test_unittest_skipunless.py.fixture
  py-unittest/good/test_unittest_skipunless_split.py.fixture
  py-unittest/good/test_unittest_slugify.py.fixture
)
on_disk="$(cd "$CORPUS" && find . -type f -name '*.fixture' | sed 's|^\./||' | sort)"
listed="$(printf '%s\n' "${corpus_files[@]}" | sort)"
if [[ "$on_disk" == "$listed" ]]; then
  pass "every corpus file is listed, and every listed file exists"
else
  fail "corpus list matches disk" "$(diff <(printf '%s\n' "$listed") <(printf '%s\n' "$on_disk"))"
fi
# A `reads: <path>` file reads a source file by a static path: its copy sits in
# test/ under a fresh git repository that tracks a stub at <path>, so the
# driver's tracked-file check can keep the read. planted/ is no adapter's
# directory, so its files name their adapter in an `adapter: <id>` header.
reads_n=0
for rel in "${corpus_files[@]}"; do
  base="${rel##*/}"
  copy="$TMP_ROOT/corpus/${rel%/*}/${base%.fixture}"
  reads="$(sed -n 's/.*reads: \([^ ]*\).*/\1/p' "$CORPUS/$rel")"
  if [[ -n "$reads" ]]; then
    reads_n=$((reads_n + 1))
    repo="$TMP_ROOT/corpus-reads/$reads_n"
    copy="$repo/test/${base%.fixture}"
    mkdir -p "$repo/test" "$(dirname "$repo/$reads")"
    printf 'stub\n' >"$repo/$reads"
    git -C "$repo" init -q
    git -C "$repo" add -- "$reads"
  fi
  mkdir -p "${copy%/*}"
  cp "$CORPUS/$rel" "$copy"
  run_file --file "$copy"
  claim="$(sed -n 's/.*adapter: \([a-z-]*\).*/\1/p' "$CORPUS/$rel")"
  [[ -n "$claim" ]] || claim="${rel%%/*}"
  assert_contains "corpus $rel: claimed by $claim" "$out" "adapter: $claim"
  want="$(sed -n 's/.*expect: \(rule-[a-z-]*\).*/\1/p' "$copy" | sort -u | paste -sd, -)"
  got="$(printf '%s\n' "$out" | sed -n 's|^finding \[testing/audit/\(rule-[a-z-]*\)\].*|\1|p' | sort -u | paste -sd, -)"
  if [[ "$got" == "$want" ]]; then
    pass "corpus $rel: reports exactly [${want}]"
  else
    fail "corpus $rel: exact rule set" "want [$want], got [$got]"
  fi
  # An `exempt: <rule>` file fires that rule under cant-fail-ok:, which the
  # scan counts rather than drops.
  if grep -q 'exempt: rule-' "$copy"; then
    assert_contains "corpus $rel: the annotated finding is counted as exempt" "$out" "exempted findings (cant-fail-ok): 1"
  fi
done

# --- report-only rules: print, never gate -------------------------------------
# inert-assertion, constant-restatement and source-text-read are reported and
# counted, and gate neither --check nor --check --strict.
RO="$TMP_ROOT/report-only"
# ro_repo <dir> <tracked source>...: a git repository tracking stub sources.
ro_repo() {
  local dir="$1" src
  shift
  mkdir -p "$dir/test"
  git -C "$TMP_ROOT" init -q -b report-only "${dir#"$TMP_ROOT"/}"
  for src in "$@"; do
    mkdir -p "$(dirname "$dir/$src")"
    printf 'export const X = 1;\n' >"$dir/$src"
    git -C "$dir" add -- "$src"
  done
}
ro_repo "$RO/inert"
cp "$CORPUS/py-pytest/bad/test_pytest_total_tuple_assert.py.fixture" "$RO/inert/test/test_pytest_total_tuple_assert.py"
ro_repo "$RO/constant"
cp "$CORPUS/js-vitest/bad/vitest-post-limit-restated.test.ts.fixture" "$RO/constant/test/vitest-post-limit-restated.test.ts"
ro_repo "$RO/source" app/pitch-detail.tsx
cp "$CORPUS/js-vitest/bad/vitest-pitch-detail-source-order.test.ts.fixture" "$RO/source/test/vitest-pitch-detail-source-order.test.ts"
for pair in inert:rule-inert-assertion constant:rule-constant-restatement source:rule-source-text-read; do
  dir="$RO/${pair%%:*}" rule="${pair#*:}"
  run_scan "$dir" --check
  assert_exit "(a) --check passes a tree whose only finding is $rule (exit 0)" 0 "$rc"
  assert_contains "(a) --check still prints the $rule finding" "$out" "finding [testing/audit/$rule]"
  assert_contains "(a) --check names $rule report-only" "$out" "report-only and never gate --check, --strict included"
  run_scan "$dir" --check --strict
  assert_exit "(a) --check --strict passes a tree whose only finding is $rule (exit 0)" 0 "$rc"
  assert_contains "(a) --check --strict still prints the $rule finding" "$out" "finding [testing/audit/$rule]"
done
# (c) the whole-tree walk, not --file, resolves the read against the tracked source.
run_scan "$RO/source"
assert_contains "(c) a whole-tree run reports the T2 read of its tracked source" "$out" \
  "test/vitest-pitch-detail-source-order.test.ts:12: reads tracked source file app/pitch-detail.tsx as text"
git -C "$RO/source" rm -q --cached app/pitch-detail.tsx
run_scan "$RO/source"
assert_not_contains "(c) the same read of an untracked file is no finding" "$out" "rule-source-text-read"

# (b) a file the test wrote itself, and reads through a glob or a directory
# walk, are never a source-text read, though the sources they reach are tracked.
ro_repo "$RO/policy" src/limits.ts src/gen.ts scripts/deploy.sh
printf '%s\n' "import { globSync, readFileSync, readdirSync, writeFileSync } from 'fs';" \
  "import { join } from 'path';" "import { tmpdir } from 'os';" \
  "test('reads back what it wrote', () => {" "  const out = join(tmpdir(), 'gen.ts');" \
  "  writeFileSync(out, 'x');" "  expect(readFileSync(out, 'utf8')).toBe('x');" "});" \
  "test('no debugger in any source', () => {" "  for (const f of globSync('src/*.ts')) {" \
  "    expect(readFileSync(f, 'utf8')).not.toContain('debugger');" "  }" \
  "  readdirSync('src').forEach((f) => expect(readFileSync('src/limits.ts', 'utf8')).toBeTruthy());" "});" \
  >"$RO/policy/test/policy.test.ts"
printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail' 'REPO="$(cd "$(dirname "$0")/.." && pwd)"' \
  'TMP="$(mktemp -d)"' 'cp "$REPO/scripts/deploy.sh" "$TMP/deploy.sh"' \
  'grep -q pipefail "$TMP/deploy.sh" || fail "copy"' \
  'for f in "$REPO"/scripts/*.sh; do grep -q pipefail "$f" || fail "$f"; done' \
  'find "$REPO/src" -name "*.ts" -exec grep -L x {} + >/dev/null' 'pass policy' >"$RO/policy/test/policy.test.sh"
run_scan "$RO/policy"
assert_contains "(b) the policy tree was examined" "$out" "test files: 2 examined of 2 enumerated"
assert_not_contains "(b) a self-written file, a glob and a walk are never a source-text read" "$out" "rule-source-text-read"

# (d) a contract constant under cant-fail-ok: is exempt, and counted.
printf '%s\n' "import { X_POST_CHARACTER_LIMIT } from '../src/post';" \
  "test('the API caps posts at 280', () => {" "  // cant-fail-ok: the 280 limit is fixed by the X API contract" \
  "  expect(X_POST_CHARACTER_LIMIT).toBe(280);" "});" >"$RO/contract.test.ts"
run_file --file "$RO/contract.test.ts"
assert_not_contains "(d) an annotated constant restatement is not reported" "$out" "rule-constant-restatement"
assert_contains "(d) the annotated constant restatement is counted as exempt" "$out" "exempted findings (cant-fail-ok): 1"

# Remedies, pinned per scope: each rule's Action is asserted where it fires,
# and asserted absent where the advice would not apply.
# remedy <corpus copy> <rule>: the Action text of that rule's finding.
remedy() {
  run_file --file "$1"
  printf '%s\n' "$out" | sed -n "s|^finding \[testing/audit/$2\].*Action: ||p" | head -1
}
C="$TMP_ROOT/corpus"
a="$(remedy "$C/js-playwright/bad/playwright-saved-unawaited.spec.ts" rule-inert-assertion)"
assert_contains "inert remedy (js) says to await the matcher" "$a" "await (or return) the async matcher"
assert_not_contains "inert remedy (js) offers no Python tuple advice" "$a" "tuple"
a="$(remedy "$C/cs-xunit/bad/InvoiceShouldAloneTests.cs" rule-inert-assertion)"
assert_contains "inert remedy (cs) names await and a chained matcher" "$a" "chain a matcher after .Should()"
assert_not_contains "inert remedy (cs) offers no bats advice" "$a" '$status'
a="$(remedy "$C/py-pytest/bad/test_pytest_total_tuple_assert.py" rule-inert-assertion)"
assert_contains "inert remedy (python) says to drop the tuple and use assert_*" "$a" "assert_called_once_with"
assert_not_contains "inert remedy (python) never says await" "$a" "await"
a="$(remedy "$C/bash-bats/bad/bats-greet-run-unchecked.bats" rule-inert-assertion)"
assert_contains "inert remedy (bash) says to check what run captured" "$a" 'check what run captured ($status'
assert_not_contains "inert remedy (bash) never says await" "$a" "await"
a="$(remedy "$C/pwsh-pester/bad/pester-sum-bare-comparison.Tests.ps1" rule-inert-assertion)"
assert_contains "inert remedy (pwsh) says to pipe to Should" "$a" "Should -Be 5"
assert_not_contains "inert remedy (pwsh) never says await" "$a" "await"
a="$(remedy "$C/go-testing/bad/go_slugify_logs_mismatch_test.go" rule-inert-assertion)"
assert_contains "inert remedy (go) says to fail with t.Errorf" "$a" "t.Errorf or t.Fatalf"
assert_not_contains "inert remedy (go) never says await" "$a" "await"
for f in js-jest/bad/jest-upload-limit-restated.test.ts py-pytest/bad/test_pytest_limit_restated.py \
  bash-bats/bad/bats-retry-limit-restated.bats; do
  a="$(remedy "$C/$f" rule-constant-restatement)"
  assert_contains "constant remedy ($f) asserts behavior or records a contract constant" "$a" \
    "Assert the behavior that uses the constant"
  assert_contains "constant remedy ($f) names the cant-fail-ok: exemption" "$a" "cant-fail-ok: <why>"
  assert_not_contains "constant remedy ($f) is not the inert remedy" "$a" "Make the assertion evaluate"
done
while IFS= read -r f; do
  a="$(remedy "$f" rule-source-text-read)"
  assert_contains "source remedy (${f##*/}) says to exercise the code" "$a" "Exercise the code (render it, call it, run it)"
  assert_contains "source remedy (${f##*/}) routes policy tests to a glob or walk" "$a" "a glob or a directory walk"
  assert_not_contains "source remedy (${f##*/}) never offers the cant-fail-ok escape" "$a" "cant-fail-ok"
done < <(find "$TMP_ROOT/corpus-reads" -path '*/test/*' \( -name 'jest-checkout-source-text.test.ts' \
  -o -name 'test_pytest_views_source_text.py' -o -name 'deploy-source-text.test.sh' \) | sort)
# The findings file carries the per-rule tier: change detectors below the can't-fail rules.
cp "$CORPUS/py-pytest/bad/test_pytest_total_tuple_assert.py.fixture" "$RO/constant/test/test_pytest_total_tuple_assert.py"
cp "$CORPUS/js-vitest/bad/vitest-pitch-detail-source-order.test.ts.fixture" "$RO/constant/test/vitest-pitch-detail-source-order.test.ts"
mkdir -p "$RO/constant/app"
printf 'x\n' >"$RO/constant/app/pitch-detail.tsx"
git -C "$RO/constant" add app/pitch-detail.tsx
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$RO/constant" bash "$SCAN" --findings 2>/dev/null)" || rc=$?
assert_exit "--findings persists report-only findings" 0 "$rc"
assert_matches "an inert-assertion row is IMPORTANT with high confidence" "$out" \
  '^\| [0-9]+ \| IMPORTANT \| high \| test/test_pytest_total_tuple_assert.py:8 \|'
assert_matches "a constant-restatement row is SUGGESTION with Confidence omitted" "$out" \
  '^\| [0-9]+ \| SUGGESTION \|  \| test/vitest-post-limit-restated.test.ts:10 \|'
assert_matches "a source-text-read row is SUGGESTION with Confidence omitted" "$out" \
  '^\| [0-9]+ \| SUGGESTION \|  \| test/vitest-pitch-detail-source-order.test.ts:12 \|'
assert_contains "Surfaces counts the report-only rules" "$out" \
  "report-only findings (never gate --check): testing/audit/rule-inert-assertion 1, testing/audit/rule-constant-restatement 1, testing/audit/rule-source-text-read 1"

# --- Phase 4b report-only rules -------------------------------------------------
# (a) conditional-assertion, recomputed-derived, snapshot-only and weak-oracle
# print, and gate neither --check nor --check --strict.
for pair in cond:rule-conditional-assertion:js-vitest/bad/vitest-rows-loop-unchecked.test.ts \
  derived:rule-recomputed-derived:py-pytest/bad/test_pytest_price_sum_recomputed.py \
  snap:rule-snapshot-only:js-jest/bad/jest-receipt-snapshot.test.ts \
  weak:rule-weak-oracle:cs-xunit/bad/InvoiceNotNullTests.cs; do
  IFS=: read -r name rule rel <<<"$pair"
  ro_repo "$RO/$name"
  cp "$CORPUS/$rel.fixture" "$RO/$name/test/${rel##*/}"
  run_scan "$RO/$name" --check
  assert_exit "(a) --check passes a tree whose only finding is $rule (exit 0)" 0 "$rc"
  assert_contains "(a) --check still prints the $rule finding" "$out" "finding [testing/audit/$rule]"
  assert_contains "(a) --check names $rule report-only" "$out" "report-only and never gate --check, --strict included"
  run_scan "$RO/$name" --check --strict
  assert_exit "(a) --check --strict passes a tree whose only finding is $rule (exit 0)" 0 "$rc"
  assert_contains "(a) --check --strict still prints the $rule finding" "$out" "finding [testing/audit/$rule]"
done

# Each "gives 0 findings" case below runs beside a control: the same body
# without the exemption fires, so the silent run cannot pass vacuously.
# b4 <file> <line>...: write a test file under $B4 from its lines.
B4="$TMP_ROOT/b4"
mkdir -p "$B4"
b4() {
  local f="$B4/$1"
  shift
  printf '%s\n' "$@" >"$f"
  run_file --file "$f"
}

# (b) the snapshot-only finding says to review the snapshot as code, and an
# image comparison is never a snapshot finding.
b4 aria.spec.ts "import { expect, test } from '@playwright/test';" "test('nav', async ({ page }) => {" \
  "  await expect(page.getByRole('navigation')).toMatchAriaSnapshot();" "});"
assert_contains "(b) control: an aria snapshot alone fires snapshot-only" "$out" "rule-snapshot-only"
assert_contains "(b) the finding says snapshot is the only oracle: review it as code" "$out" \
  "snapshot is the only oracle: review it as code"
b4 shot.spec.ts "import { expect, test } from '@playwright/test';" "test('nav', async ({ page }) => {" \
  "  await expect(page).toHaveScreenshot();" "});"
assert_contains "(b) the screenshot test was parsed" "$out" "test blocks parsed: 1;"
assert_finding_count "(b) a toHaveScreenshot test gives 0 findings" 0

# (c) a derived expectation in a property-test file, or in a Playwright file,
# gives 0 findings; the same body elsewhere fires.
DERIVED_JS=("test('adds', () => {" "  expect(add(a, b)).toBe(a + b);" "});")
b4 derived.test.ts "import { expect, test } from 'vitest';" "${DERIVED_JS[@]}"
assert_contains "(c) control: the vitest body fires recomputed-derived" "$out" "rule-recomputed-derived"
b4 derived-fc.test.ts "import { expect, test } from 'vitest';" "import fc from 'fast-check';" "${DERIVED_JS[@]}" \
  "test('commutes', () => {" "  fc.assert(fc.property(fc.integer(), fc.integer(), (a, b) => add(a, b) === add(b, a)));" "});"
assert_finding_count "(c) the same body in a fast-check file gives 0 findings" 0
b4 derived.spec.ts "import { expect, test } from '@playwright/test';" "${DERIVED_JS[@]}"
assert_contains "(c) the Playwright file was parsed" "$out" "test blocks parsed: 1;"
assert_finding_count "(c) the same body in a js-playwright file gives 0 findings" 0
b4 test_derived.py "def test_adds():" "    assert add(a, b) == a + b"
assert_contains "(c) control: the pytest body fires recomputed-derived" "$out" "rule-recomputed-derived"
b4 test_derived_given.py "from hypothesis import given, strategies as st" "" "" "@given(st.integers(), st.integers())" \
  "def test_adds(a, b):" "    assert add(a, b) == a + b"
assert_finding_count "(c) the same body under @given gives 0 findings" 0
GO_DERIVED=("func TestAdd(t *testing.T) {" "	if !reflect.DeepEqual(Add(a, b), a+b) {" "		t.Error(a, b)" "	}" "}")
b4 derived_test.go "package calc" "" 'import "reflect"' "" "${GO_DERIVED[@]}"
assert_contains "(c) control: the go body fires recomputed-derived" "$out" "rule-recomputed-derived"
b4 derived_quick_test.go "package calc" "" 'import (' '	"reflect"' '	"testing/quick"' ')' "" "${GO_DERIVED[@]}"
assert_finding_count "(c) the same body in a testing/quick file gives 0 findings" 0

# (d) an assertion inside a loop over a result, with a length check, gives 0
# findings; without the check it fires.
LOOP_JS=("  const rows = await activeUsers();" "  for (const row of rows) {" "    expect(row.active).toBe(true);" "  }" "});")
b4 loop.test.ts "import { expect, it } from 'vitest';" "it('rows', async () => {" "${LOOP_JS[@]}"
assert_contains "(d) control: the loop alone fires conditional-assertion" "$out" "rule-conditional-assertion"
b4 loop-checked.test.ts "import { expect, it } from 'vitest';" "it('rows', async () => {" "  expect(await activeUsers()).toHaveLength(2);" \
  "${LOOP_JS[@]}"
assert_finding_count "(d) the same loop after a length check gives 0 findings" 0

# (e) toBeDefined beside a value assertion gives 0 findings; alone it fires.
b4 defined.test.ts "import { expect, it } from 'vitest';" "it('user', async () => {" "  const user = await createUser('ada');" \
  "  expect(user).toBeDefined();" "});"
assert_contains "(e) control: toBeDefined alone fires weak-oracle" "$out" "rule-weak-oracle"
b4 defined-beside.test.ts "import { expect, it } from 'vitest';" "it('user', async () => {" "  const user = await createUser('ada');" \
  "  expect(user).toBeDefined();" "  expect(user.name).toBe('ada');" "});"
assert_finding_count "(e) toBeDefined beside a value assertion gives 0 findings" 0

# Remedies for the four rules, asserted in each language they fire in here.
for f in js-vitest/bad/vitest-rows-loop-unchecked.test.ts py-unittest/bad/test_unittest_parse_except_only.py \
  cs-nunit/bad/CartPlaceOrderCatchTests.cs; do
  a="$(remedy "$C/$f" rule-conditional-assertion)"
  assert_contains "conditional remedy ($f) makes every path assert" "$a" "Make every path assert"
  assert_contains "conditional remedy ($f) asks for a length check before a loop" "$a" "assert the length of a result before looping over it"
  assert_not_contains "conditional remedy ($f) is not the inert remedy" "$a" "Make the assertion evaluate"
done
for f in js-vitest/bad/vitest-order-total-recomputed.test.ts py-unittest/bad/test_unittest_total_recomputed.py \
  cs-mstest/bad/OrderLinesSumTests.cs pwsh-pester/bad/pester-total-measure-derived.Tests.ps1; do
  a="$(remedy "$C/$f" rule-recomputed-derived)"
  assert_contains "derived remedy ($f) states the value independently" "$a" "State the expected value independently"
  assert_not_contains "derived remedy ($f) is not the self-identical remedy" "$a" "recomputing it with the same expression"
done
for f in js-jest/bad/jest-receipt-snapshot.test.ts py-pytest/bad/test_pytest_render_snapshot.py \
  go-testing/bad/go_render_snapshot_test.go; do
  a="$(remedy "$C/$f" rule-snapshot-only)"
  assert_contains "snapshot remedy ($f) reviews it and adds a literal" "$a" "Review the snapshot as code"
  assert_not_contains "snapshot remedy ($f) never removes the snapshot" "$a" "remove"
done
for f in js-jest/bad/jest-create-user-defined-verbatim.test.ts py-unittest/bad/test_unittest_parse_raises_exception.py \
  go-testing/bad/go_user_nil_check_test.go pwsh-pester/bad/pester-report-not-empty.Tests.ps1; do
  a="$(remedy "$C/$f" rule-weak-oracle)"
  assert_contains "weak remedy ($f) asks for the exact value or exception" "$a" "Assert the value the code should produce"
  assert_not_contains "weak remedy ($f) is not the zero-assertion remedy" "$a" "passes vacuously"
done

# The findings file carries the tiers: conditional is can't-fail; derived,
# snapshot-only and weak-oracle can fail.
for name in cond derived snap weak; do cp "$RO/$name/test/"* "$RO/constant/test/"; done
rc=0
out="$(CANT_FAIL_SCAN_ROOT="$RO/constant" bash "$SCAN" --findings 2>/dev/null)" || rc=$?
assert_exit "--findings persists the 4b report-only findings" 0 "$rc"
assert_matches "a conditional-assertion row is IMPORTANT with Confidence omitted" "$out" \
  '^\| [0-9]+ \| IMPORTANT \|  \| test/vitest-rows-loop-unchecked.test.ts:10 \|'
assert_matches "a recomputed-derived row is SUGGESTION with Confidence omitted" "$out" \
  '^\| [0-9]+ \| SUGGESTION \|  \| test/test_pytest_price_sum_recomputed.py:9 \|'
assert_matches "a snapshot-only row is SUGGESTION" "$out" '^\| [0-9]+ \| SUGGESTION \|  \| test/jest-receipt-snapshot.test.ts:8 \|'
assert_matches "a weak-oracle row is SUGGESTION" "$out" '^\| [0-9]+ \| SUGGESTION \|  \| test/InvoiceNotNullTests.cs:11 \|'
assert_contains "Surfaces counts the 4b report-only rules" "$out" \
  "testing/audit/rule-conditional-assertion 1, testing/audit/rule-recomputed-derived 1, testing/audit/rule-snapshot-only 1, testing/audit/rule-weak-oracle 1"

# (e), and 4b (f): every rule id the scanner can emit, the seven report-only
# rules included, has a positive evals.json expectation.
EVALS="$SCRIPT_DIR/../evals/evals.json"
expected="$(jq -r '.evals[] | .expected_output, .expectations[]' "$EVALS")"
emitted="$({
  grep -ohE 'emit\([^,]*, "[a-z-]+"' "$SCRIPT_DIR/cant-fail-scan.awk" "$SCRIPT_DIR/runner-config-scan.awk"
  grep -ohE 'slug=[a-z-]+' "$SCRIPT_DIR/cant-fail-scan.sh"
} | sed -E 's/.*[" =]([a-z-]+)"?$/\1/' | sort -u)"
if [[ "$(printf '%s\n' "$emitted" | grep -c .)" -ge 12 ]]; then
  pass "(e) the emitted rule ids were extracted from the engines"
else
  fail "(e) the emitted rule ids were extracted from the engines" "got: $emitted"
fi
while IFS= read -r slug; do
  assert_contains "(e) evals.json expects testing/audit/rule-$slug" "$expected" "testing/audit/rule-$slug"
done <<<"$emitted"

# --- corpus grid: GRID.md rows and pair cells ---------------------------------
GRIDCHK="$SCRIPT_DIR/check-corpus-grid.sh"
rc=0
out="$(bash "$GRIDCHK" 2>&1)" || rc=$?
assert_exit "the shipped corpus satisfies GRID.md" 0 "$rc"
[[ "$rc" -eq 0 ]] || printf '%s\n' "$out" >&2
G="$TMP_ROOT/grid"
mkdir -p "$G/corpus/a/bad" "$G/corpus/a/good" "$G/adapters"
printf 'id: a\n' >"$G/adapters/a.yaml"
printf '| Adapter | rule-x |\n|---|---|\n| a | pair |\n' >"$G/corpus/GRID.md"
printf '# expect: rule-x\n' >"$G/corpus/a/bad/b.fixture"
rc=0
out="$(bash "$GRIDCHK" "$G/corpus" "$G/adapters" 2>&1)" || rc=$?
assert_exit "a pair cell with no good file fails the grid" 1 "$rc"
assert_contains "the grid names the missing good file" "$out" "a: pair cell for rule-x has no good file with 'good-for: rule-x'"
printf '# good-for: rule-x\n' >"$G/corpus/a/good/g.fixture"
printf 'id: b\n' >"$G/adapters/b.yaml"
rc=0
out="$(bash "$GRIDCHK" "$G/corpus" "$G/adapters" 2>&1)" || rc=$?
assert_exit "an adapter with no GRID.md row fails the grid" 1 "$rc"
assert_contains "the grid names the rowless adapter" "$out" "adapter b has no GRID.md row"
printf '| b | maybe |\n' >>"$G/corpus/GRID.md"
rc=0
out="$(bash "$GRIDCHK" "$G/corpus" "$G/adapters" 2>&1)" || rc=$?
assert_contains "a cell that is neither pair nor n/a fails the grid" "$out" "b: cell for rule-x is 'maybe'"
printf '| Adapter | rule-x |\n|---|---|\n| a | pair |\n| b | n/a: no such shape |\n' >"$G/corpus/GRID.md"
rc=0
bash "$GRIDCHK" "$G/corpus" "$G/adapters" >/dev/null 2>&1 || rc=$?
assert_exit "pair cells with both files and n/a cells pass the grid" 0 "$rc"
printf '\n| Id | Rule or judge |\n|---|---|\n| T3 | judge |\n' >>"$G/corpus/GRID.md"
rc=0
out="$(bash "$GRIDCHK" "$G/corpus" "$G/adapters" 2>&1)" || rc=$?
assert_exit "a second table after the Adapter grid is not read as adapter rows" 0 "$rc"
assert_not_contains "the second table's rows are never named as adapters" "$out" "T3"

# --- .claude/testing.yaml: the config cascade ---------------------------------
# HOME and CLAUDE_PROJECT_DIR are pinned per run: a developer's own layers must
# not change what these cases see.
CFG="$TMP_ROOT/cfg"
CFG_HOME="$TMP_ROOT/cfg-home"
mkdir -p "$CFG/.claude" "$CFG/src" "$CFG/build/t" "$CFG_HOME"
git -C "$CFG" init -q
printf "import { it } from 'vitest';\nit('adds', () => {\n  add(1, 2);\n});\n" >"$CFG/src/bad.test.ts"
printf "import { it, expect } from 'vitest';\nit('adds', () => {\n  expect(add(1, 2)).toBeDefined();\n});\n" >"$CFG/src/weak.test.ts"
printf 'package x\n\nimport "testing"\n\nfunc TestSum(t *testing.T) {\n\tSum(1, 2)\n}\n' >"$CFG/src/sum_test.go"
cp "$CFG/src/bad.test.ts" "$CFG/src/bad.it.ts"
cp "$CFG/src/bad.test.ts" "$CFG/build/t/built.test.ts"
cfg_scan() {
  rc=0
  out="$(env -u CLAUDE_PROJECT_DIR HOME="$CFG_HOME" CANT_FAIL_SCAN_ROOT="$CFG" bash "$SCAN" "$@" 2>&1)" || rc=$?
}
cfg_set() { printf '%s\n' "$@" >"$CFG/.claude/testing.yaml"; }

cfg_scan
assert_finding_count "no config: the zero-assertion, weak-oracle and Go findings" 3
cfg_set 'paths:' "  exclude: ['**/*.test.ts']"
cfg_scan
assert_finding_count "paths.exclude '**/*.test.ts' drops both .test.ts files" 1
assert_contains "the coverage block counts the excluded files" "$out" "excluded by paths.exclude: 2"
cfg_scan --file "$CFG/src/bad.test.ts"
assert_finding_count "--file of an excluded path reports nothing" 0
assert_contains "and examines nothing" "$out" "test files: 0 examined"
hook_out="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Write","session_id":"s","tool_use_id":"cfg-1","tool_input":{"file_path":"%s"},"tool_response":{"type":"create","structuredPatch":[]}}' "$CFG/src/bad.test.ts" |
  env -u CLAUDE_PROJECT_DIR HOME="$CFG_HOME" CLAUDE_PLUGIN_DATA="$TMP_ROOT/cfg-data" CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED=true \
    bash "$SCRIPT_DIR/../../../hooks/test-scan.sh" 2>&1)"
if [[ -z "$hook_out" ]]; then pass "test-scan.sh prints nothing for an excluded test file"; else fail "test-scan.sh prints nothing for an excluded test file" "$hook_out"; fi
cfg_set 'adapters:' '  disable: [go-testing]'
cfg_scan
assert_finding_count "adapters.disable drops the Go file" 2
assert_contains "the Go file is not even enumerated" "$out" "go 0)"
cfg_set 'adapters:' '  enable: [go-testing]'
cfg_scan
assert_finding_count "adapters.enable runs only the listed adapters" 1
cfg_set 'rules:' '  rule-zero-assertion: off'
cfg_scan --check
assert_finding_count "rules off drops the finding" 1
assert_exit "with no gating finding left, --check passes" 0 "$rc"
cfg_set 'rules:' '  rule-zero-assertion: warn'
cfg_scan --check
assert_finding_count "rules warn still reports" 3
assert_exit "but never gates --check" 0 "$rc"
cfg_set 'rules:' '  rule-zero-assertion: warn' '  testing/audit/rule-weak-oracle: error'
cfg_scan --check
assert_exit "rules error gates a report-only rule" 1 "$rc"
assert_contains "and counts one gating finding" "$out" "FAIL: 1 gating finding(s)."
cfg_set 'extend:' '  js-vitest:' "    files: ['*.it.ts']"
cfg_scan
assert_finding_count "extend.js-vitest.files claims a new glob" 4
assert_contains "the audit names the glob no hook row covers" "$out" "*.it.ts"
cfg_set 'paths:' "  include: ['build/**/*.test.ts']"
cfg_scan
assert_finding_count "paths.include reaches a pruned directory" 4
assert_contains "the included file is reported" "$out" "build/t/built.test.ts"
cfg_set 'rules:' '  test-weaken-block: error'
cfg_scan --file "$CFG/src/bad.test.ts" --inventory "$CFG/src/bad.test.ts"
assert_exit "rules.test-weaken-block is a valid key" 0 "$rc"
assert_matches "--inventory prints the resolved test-weaken-block level" "$out" $'^rule\ttest-weaken-block\terror$'
assert_matches "and the inventory beside it" "$out" $'^1\ttest\t1\t'
cfg_set 'paths:' "  exclude: ['**/*.test.ts']"
cfg_scan --file "$CFG/src/bad.test.ts" --inventory "$CFG/src/bad.test.ts"
assert_not_contains "--inventory of an excluded path prints no inventory" "$out" $'1\ttest'
cfg_set 'rules:' '  rule-no-such: off'
cfg_scan
assert_exit "an invalid config refuses the scan" 2 "$rc"
# A disabled adapter's file is silenced, never handed to a sibling that also
# claims its name: js-jest claims *.test.ts, py-unittest test_*.py.
cfg_hook() {
  printf '{"hook_event_name":"PostToolUse","tool_name":"Write","session_id":"s","tool_use_id":"%s","tool_input":{"file_path":"%s"},"tool_response":{"type":"create","structuredPatch":[]}}' "$1" "$2" |
    env -u CLAUDE_PROJECT_DIR HOME="$CFG_HOME" CLAUDE_PLUGIN_DATA="$TMP_ROOT/cfg-data" CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED=true \
      bash "$SCRIPT_DIR/../../../hooks/test-scan.sh" 2>&1
}
printf 'def test_x():\n    add(1, 2)\n' >"$CFG/src/test_x.py"
cfg_set 'adapters:' '  disable: [js-vitest, py-pytest]'
cfg_scan --file "$CFG/src/bad.test.ts"
assert_contains "disable js-vitest: a vitest file is not handed to js-jest" "$out" "test files: 0 examined"
cfg_scan --file "$CFG/src/test_x.py"
assert_contains "disable py-pytest: a pytest file is not handed to py-unittest" "$out" "test files: 0 examined"
cfg_scan
assert_not_contains "and the audit reports neither" "$out" "bad.test.ts"
assert_not_contains "nor the pytest file" "$out" "test_x.py"
hook_out="$(cfg_hook cfg-dis-1 "$CFG/src/bad.test.ts")$(cfg_hook cfg-dis-2 "$CFG/src/test_x.py")"
if [[ -z "$hook_out" ]]; then pass "test-scan.sh is silent on both"; else fail "test-scan.sh is silent on both" "$hook_out"; fi
cfg_set 'adapters:' '  enable: [js-jest]'
cfg_scan --file "$CFG/src/bad.test.ts"
assert_contains "an enable allowlist without js-vitest silences a vitest file too" "$out" "test files: 0 examined"
rm -f "$CFG/src/test_x.py"
# rules error: a report-only rule that now gates is not called report-only.
cfg_set 'rules:' '  rule-weak-oracle: error'
cfg_scan --check
assert_not_contains "a rule at error is left out of the report-only note" "$out" "weak-oracle 1"
# A UTF-8 byte-order mark at the start of a layer is not part of its first key.
printf '\357\273\277paths:\n  exclude: [src/sum_test.go]\n' >"$CFG/.claude/testing.yaml"
cfg_scan
assert_exit "a layer starting with a UTF-8 BOM loads" 0 "$rc"
assert_finding_count "and applies" 2
# The team layer is the scanned repository's own, not CLAUDE_PROJECT_DIR's:
# a sibling worktree or repository uses its own config.
OTHER="$TMP_ROOT/cfg-other"
mkdir -p "$OTHER/.claude" "$OTHER/src"
git -C "$OTHER" init -q
cp "$CFG/src/bad.test.ts" "$OTHER/src/bad.test.ts"
printf 'adapters:\n  disable: [js-vitest]\n' >"$OTHER/.claude/testing.yaml"
rm -f "$CFG/.claude/testing.yaml"
rc=0
out="$(CLAUDE_PROJECT_DIR="$CFG" HOME="$CFG_HOME" bash "$SCAN" --file "$OTHER/src/bad.test.ts" 2>&1)" || rc=$?
assert_contains "a file in another repository gets that repository's team layer" "$out" "test files: 0 examined"
rc=0
out="$(CLAUDE_PROJECT_DIR="$OTHER" HOME="$CFG_HOME" bash "$SCAN" --file "$CFG/src/bad.test.ts" 2>&1)" || rc=$?
assert_contains "and CLAUDE_PROJECT_DIR's layer does not leak into it" "$out" "rule-zero-assertion"
rm -f "$CFG/.claude/testing.yaml"
mkdir -p "$CFG_HOME/.claude"
printf 'paths:\n  exclude: [src/sum_test.go]\n' >"$CFG_HOME/.claude/testing.yaml"
cfg_scan
assert_finding_count "the user-global layer applies" 2
rm -f "$CFG_HOME/.claude/testing.yaml"

# --- the whole suite again under mawk -----------------------------------------
# A gawk-only pass does not count: the engine must hold under mawk as well.
if [[ -z "${CANT_FAIL_TEST_MAWK_LEG:-}" ]] && command -v mawk >/dev/null 2>&1; then
  mkdir -p "$TMP_ROOT/mawk-shim"
  ln -sf "$(command -v mawk)" "$TMP_ROOT/mawk-shim/awk"
  rc=0
  mawk_out="$(CANT_FAIL_TEST_MAWK_LEG=1 PATH="$TMP_ROOT/mawk-shim:$PATH" bash "${BASH_SOURCE[0]}" 2>&1)" || rc=$?
  assert_matches "the shim resolves awk to mawk" "$(PATH="$TMP_ROOT/mawk-shim:$PATH" awk -W version 2>&1 | head -1)" '^mawk'
  assert_exit "the whole suite passes under mawk" 0 "$rc"
  [[ "$rc" -eq 0 ]] || printf '%s\n' "$mawk_out" | grep -A1 '^FAIL' >&2
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
