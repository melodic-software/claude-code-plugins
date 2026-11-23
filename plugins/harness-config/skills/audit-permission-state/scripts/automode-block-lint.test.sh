#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/automode-block-lint.sh"
FIXTURES="$SCRIPT_DIR/../evals/fixtures"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
  echo "SKIP: python3 not installed — this lane is optional by design" >&2
  exit 0
fi

CONFIG="$FIXTURES/automode-config-rawctl.json"
DEFAULTS="$FIXTURES/automode-defaults.json"

run() {
  env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" bash "$SCRIPT"
}

if command -v jq >/dev/null 2>&1; then
  jq_rc=0
  jq -e . "$CONFIG" >/dev/null 2>&1 || jq_rc=$?
  if [[ "$jq_rc" -ne 0 ]]; then
    pass "the fixture really does carry a raw control character (jq rejects it)"
  else
    fail "the fixture really does carry a raw control character (jq rejects it)" \
      "jq parsed it cleanly, so this suite is not testing the measured defect"
  fi
else
  pass "strict-parser rejection (skipped — jq not installed)"
fi

OUT=$(run)
assert_contains "the non-strict reader parses what jq cannot" "$OUT" "status=read"
assert_contains "all four sections are seen" "$OUT" "sections=4"

assert_contains "a bracketed label is cut at the bracket" "$OUT" "First missing: Git Destructive"
assert_not_contains "the annotation is not carried into the label" "$OUT" "named+specifics"

assert_eq "exactly one section is reported as discarding its defaults" 1 "$(count_matching "$OUT" '\[C4-defaults\]')"
assert_contains "the finding names the section" "$OUT" "[C4-defaults] soft_deny"
assert_contains "and states how many entries are gone" "$OUT" "1 of the 2 built-in"
assert_contains "and states the mechanic rather than just the symptom" "$OUT" "REPLACES the built-in list"

assert_not_contains "an expanded-but-untouched section does not fire" "$OUT" "[C4-defaults] environment"
assert_not_contains "nor does one identical to the built-in list" "$OUT" "[C4-defaults] hard_deny"

assert_not_contains "a section carrying \$defaults does not fire" "$OUT" "[C4-defaults] allow"

assert_eq "the contradiction fires once" 1 "$(count_matching "$OUT" '\[C2b-contradiction\]')"
assert_contains "it names both sections to reconcile" "$OUT" "appears in both allow and hard_deny"

assert_eq "the shadowed entry fires once" 1 "$(count_matching "$OUT" '\[C3-shadowed\]')"
assert_contains "it says why the entry can never fire" "$OUT" "cannot be overridden"
assert_not_contains "a fixture with no dates or issue references raises no provenance finding" "$OUT" "[C5-provenance]"

PROV_CONFIG="$TEST_TMPDIR/config-provenance.json"
PROV_DEFAULTS="$TEST_TMPDIR/defaults-provenance.json"
printf '%s\n' '{"allow": ["Dated Rule: allowed since 2026-10-30 by the owner.", "Ticket Rule: see acme/repo#123.", "Bare Rule: per #45.", "Url Rule: per https://github.com/acme/repo/issues/7.", "Lang Rule: C#3 builds and https://example.com/page#4 docs.", "Clean Rule: reads in this repository."], "soft_deny": ["Built In: shipped entry dated 2025-01-01."]}' >"$PROV_CONFIG"
printf '%s\n' '{"allow": [], "soft_deny": ["Built In: shipped entry dated 2025-01-01."]}' >"$PROV_DEFAULTS"
OUT_PROV=$(env AUTOMODE_CONFIG_FIXTURE="$PROV_CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$PROV_DEFAULTS" bash "$SCRIPT")
assert_eq "each operator entry with provenance text fires once" 4 "$(count_matching "$OUT_PROV" '\[C5-provenance\]')"
assert_contains "a date is named" "$OUT_PROV" '"Dated Rule" carries provenance text (2026-10-30)'
assert_contains "an issue reference is named" "$OUT_PROV" '"Ticket Rule" carries provenance text (acme/repo#123)'
assert_contains "a bare issue number is named" "$OUT_PROV" '"Bare Rule" carries provenance text (#45)'
assert_contains "an issue URL is named" "$OUT_PROV" '"Url Rule" carries provenance text (https://github.com/acme/repo/issues/7)'
assert_not_contains "a language name or a page fragment is not an issue reference" "$OUT_PROV" '"Lang Rule"'
assert_not_contains "a clean entry does not fire" "$OUT_PROV" '"Clean Rule"'
assert_not_contains "a built-in entry is not the operator's to edit" "$OUT_PROV" '"Built In"'

MISSING_KEY="$TEST_TMPDIR/defaults-missing-key.json"
printf '{"allow": ["Only Section: one entry."]}\n' >"$MISSING_KEY"
OUT_MISSING=$(env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$MISSING_KEY" bash "$SCRIPT")
rc=$?
assert_exit "a defaults payload missing three keys does not crash the reader" 0 "$rc"
assert_contains "and the run still reports its status" "$OUT_MISSING" "status=read"
assert_not_contains "a missing key raises no defaults finding for that section" "$OUT_MISSING" "[C4-defaults] soft_deny"

EMPTY_CONFIG="$TEST_TMPDIR/config-empty.json"
printf '{}\n' >"$EMPTY_CONFIG"
OUT_EMPTY=$(env AUTOMODE_CONFIG_FIXTURE="$EMPTY_CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" bash "$SCRIPT")
assert_contains "a config with no sections is read, not crashed on" "$OUT_EMPTY" "sections=0"
assert_contains "and reports no findings rather than failing" "$OUT_EMPTY" "findings=0"

EMPTY_OUT="$TEST_TMPDIR/empty.json"
: >"$EMPTY_OUT"
OUT_NOUSE=$(env AUTOMODE_CONFIG_FIXTURE="$EMPTY_OUT" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" bash "$SCRIPT")
rc=$?
assert_exit "an empty capture still exits 0" 0 "$rc"
assert_contains "an empty capture is reported unavailable, not clean" "$OUT_NOUSE" "status=unavailable"
assert_contains "and says explicitly that it is not a clean bill" "$OUT_NOUSE" "NOT a clean bill"
assert_eq "no findings are invented from an unread block" 0 "$(count_matching "$OUT_NOUSE" '^finding ')"

GARBAGE="$TEST_TMPDIR/garbage.json"
printf 'this is not json at all\n' >"$GARBAGE"
OUT_GARBAGE=$(env AUTOMODE_CONFIG_FIXTURE="$GARBAGE" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" bash "$SCRIPT")
assert_contains "unparsable output is reported unparsable" "$OUT_GARBAGE" "status=unparsable"
assert_eq "and yields no findings" 0 "$(count_matching "$OUT_GARBAGE" '^finding ')"

STUB="$TEST_TMPDIR/stub-path"
make_stub_path "$STUB" mktemp rm cat tr tail printf
rc=0
OUT_NOPY=$(env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" \
  PATH="$STUB" "$real_bash" "$SCRIPT" 2>&1) || rc=$?
assert_exit "a missing python does not fail the run" 0 "$rc"
assert_contains "the skip notice names the lane" "$OUT_NOPY" "autoMode block lane SKIPPED"
assert_contains "and says why a POSIX fallback is not possible" "$OUT_NOPY" "non-strict JSON parser"
assert_contains "and states the blast radius" "$OUT_NOPY" "Every other stage of this skill is unaffected"
assert_contains "the summary records the skip rather than reporting zero findings" "$OUT_NOPY" "status=skipped"

TRUNCATED="$TEST_TMPDIR/critique-truncated.txt"
printf 'Your rules are mostly fine, but entry four is covered only when the resolving output is visible earlier' >"$TRUNCATED"
OUT_TRUNC=$(env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" \
  AUTOMODE_CRITIQUE_FIXTURE="$TRUNCATED" bash "$SCRIPT" --critique)
assert_contains "the critique text is surfaced verbatim" "$OUT_TRUNC" "entry four is covered only when"
assert_contains "a mid-sentence cut is called out as truncated" "$OUT_TRUNC" "appears TRUNCATED"
assert_contains "and says truncation is undetectable from exit status" "$OUT_TRUNC" "not detectable from exit status"

COMPLETE="$TEST_TMPDIR/critique-complete.txt"
printf 'Your rules look consistent and every entry states a checkable condition.\n' >"$COMPLETE"
OUT_COMPLETE=$(env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" \
  AUTOMODE_CRITIQUE_FIXTURE="$COMPLETE" bash "$SCRIPT" --critique)
assert_not_contains "a complete critique is not called truncated" "$OUT_COMPLETE" "appears TRUNCATED"

EMPTY_CRIT="$TEST_TMPDIR/critique-empty.txt"
: >"$EMPTY_CRIT"
OUT_NOCRIT=$(env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" \
  AUTOMODE_CRITIQUE_FIXTURE="$EMPTY_CRIT" bash "$SCRIPT" --critique)
assert_contains "an empty critique says so plainly" "$OUT_NOCRIT" "critique returned nothing; run it yourself"
assert_contains "and prices the claim with the measurement behind it" "$OUT_NOCRIT" "three consecutive runs"

assert_not_contains "critique is not surfaced without the flag" "$OUT" "end critique"

for shape in '[1, 2, 3]' '"hello"' '42' 'null'; do
  SHAPE_FILE="$TEST_TMPDIR/shape.json"
  printf '%s\n' "$shape" >"$SHAPE_FILE"
  rc=0
  OUT_SHAPE=$(env AUTOMODE_CONFIG_FIXTURE="$SHAPE_FILE" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" bash "$SCRIPT" 2>&1) || rc=$?
  assert_exit "a $shape payload does not crash the lane" 0 "$rc"
  assert_eq "and always emits exactly one summary line" 1 "$(count_matching "$OUT_SHAPE" '^automode summary ')"
  assert_eq "and never reports findings from a payload it could not use" 0 "$(count_matching "$OUT_SHAPE" '^finding ')"
  assert_not_contains "and never leaks a traceback" "$OUT_SHAPE" "Traceback"
done

NOTICE_STUB="$TEST_TMPDIR/notice-stub"
mkdir -p "$NOTICE_STUB"
printf '#!%s
printf "stub critique output.\n"
' "$real_bash" >"$NOTICE_STUB/claude"
chmod +x "$NOTICE_STUB/claude"
OUT_NOTICE=$(env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" PATH="$NOTICE_STUB:$PATH" bash "$SCRIPT" --critique 2>&1)
assert_contains "the critique spawn prints a cost notice" "$OUT_NOTICE" "CRITIQUE COST NOTICE"
assert_contains "the notice says nothing has been spawned yet" "$OUT_NOTICE" "nothing has been spawned yet"

rc=0
err=$(bash "$SCRIPT" --bogus </dev/null 2>&1) || rc=$?
assert_exit "exit 2 on an unknown argument" 2 "$rc"
assert_contains "the unknown argument is named" "$err" "unknown argument"

rc=0
help=$(bash "$SCRIPT" --help </dev/null 2>&1) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help states the optional-runtime contract" "$help" "exits 0 so the rest of the skill still runs"
assert_contains "--help states that reset is never run" "$help" "it never
runs 'claude auto-mode reset'"

SUBSET_CONFIG="$TEST_TMPDIR/subset-config.json"
jq '.allow = [.allow[0]]' "$DEFAULTS" >"$SUBSET_CONFIG"
OUT_SUBSET=$(env AUTOMODE_CONFIG_FIXTURE="$SUBSET_CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" bash "$SCRIPT")
assert_contains "a removal-only section is reported customized" "$OUT_SUBSET" "customized section(s): allow"
assert_not_contains "and is not called unmodified" "$OUT_SUBSET" "are the built-in lists, unmodified"
assert_contains "C4 still reports the discarded entries" "$OUT_SUBSET" "C4-defaults"

IDENTICAL_CONFIG="$TEST_TMPDIR/identical-config.json"
cp "$DEFAULTS" "$IDENTICAL_CONFIG"
OUT_IDENTICAL=$(env AUTOMODE_CONFIG_FIXTURE="$IDENTICAL_CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" bash "$SCRIPT")
assert_contains "an identical block is reported unmodified" "$OUT_IDENTICAL" "are the built-in lists, unmodified"
assert_contains "and finds nothing" "$OUT_IDENTICAL" "findings=0"

report_and_exit
