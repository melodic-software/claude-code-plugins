#!/usr/bin/env bash
# Every case feeds hand-written answer records on stdin. Nothing here reads or
# writes any settings file, in any scope: the script under test has no write
# path at all, and one case asserts exactly that.
#
# portability-scope: one fixture deliberately feeds a literal backslash through
# the drafter, to prove jq owns the JSON escaping rather than shell
# string-building. The backslash run the gate reads as a regex escape is that
# adversarial INPUT inside a heredoc, not shell code — removing it would delete
# the case rather than fix anything.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/draft-automode-block.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

draft() { printf '%s\n' "$1" | bash "$SCRIPT"; }

ANSWERS=$(
  cat <<'EOF'
section allow
label Test Execution
covered running the repository's own test suite via its documented runner
not installing new dependencies as a side effect
why the runner is named in the command text
label Formatting
covered running the repo formatter in check mode
why check mode cannot modify files
section soft_deny
label Release Publish
covered publishing a package to a public registry
why the target registry is named in the command
EOF
)

OUT=$(draft "$ANSWERS")
rc=0
printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 || rc=$?
assert_exit "the drafted block parses under a STRICT parser" 0 "$rc"

assert_eq "every emitted section opens with \$defaults" 0 \
  "$(printf '%s' "$OUT" | jq '[to_entries[] | select(.value[0] != "$defaults")] | length')"

assert_eq "only the two sections with entries are present" "allow soft_deny" \
  "$(printf '%s' "$OUT" | jq -r 'keys | join(" ")')"
assert_eq "no empty section is emitted" 0 \
  "$(printf '%s' "$OUT" | jq '[to_entries[] | select((.value | length) < 2)] | length')"

entry=$(printf '%s' "$OUT" | jq -r '.allow[1]')
assert_contains "the entry opens with its label" "$entry" "Test Execution:"
assert_contains "COVERED is its own header line" "$entry" "COVERED:"
assert_contains "and the covered item is a bullet under it" "$entry" "- running the repository's own test suite"
assert_contains "NOT COVERED is stated explicitly" "$entry" "NOT COVERED:"
assert_contains "and the exclusion is a bullet under it" "$entry" "- installing new dependencies"
assert_contains "and the rationale is one line at the end" "$entry" "Why: the runner is named in the command text"

entry2=$(printf '%s' "$OUT" | jq -r '.allow[2]')
assert_contains "an entry without exclusions still renders" "$entry2" "Formatting:"
assert_not_contains "and carries no empty NOT COVERED header" "$entry2" "NOT COVERED:"

MULTI=$(
  cat <<'EOF'
section allow
label Multi
covered first covered thing
covered second covered thing
not first excluded thing
not second excluded thing
why one line
EOF
)
OUT_MULTI=$(draft "$MULTI")
entry=$(printf '%s' "$OUT_MULTI" | jq -r '.allow[1]')
assert_contains "the first covered line appears" "$entry" "- first covered thing"
assert_contains "the second covered line appears too" "$entry" "- second covered thing"
assert_contains "the first excluded line appears" "$entry" "- first excluded thing"
assert_contains "the second excluded line appears too" "$entry" "- second excluded thing"

QUOTED=$(
  cat <<'EOF'
section allow
label Quoted "Label" And \Backslash
covered a value with "double quotes" and a \backslash and a tab	character
why it must survive intact
EOF
)
OUT_QUOTED=$(draft "$QUOTED")
rc=0
printf '%s' "$OUT_QUOTED" | jq -e . >/dev/null 2>&1 || rc=$?
assert_exit "quotes, backslashes and tabs still yield strict-valid JSON" 0 "$rc"
assert_contains "and the text survives the round trip" \
  "$(printf '%s' "$OUT_QUOTED" | jq -r '.allow[1]')" 'a value with "double quotes" and a \backslash'

NOISY=$(
  cat <<'EOF'

this line is not a record at all
section allow
label Real Entry
covered something real

EOF
)
OUT_NOISY=$(draft "$NOISY")
assert_contains "an unrecognized line does not lose the entry" "$OUT_NOISY" "Real Entry:"

ORPHAN=$(
  cat <<'EOF'
section allow
covered orphaned line with no label
label Real
covered attached correctly
EOF
)
OUT_ORPHAN=$(draft "$ORPHAN")
assert_eq "an orphaned covered line creates no entry" 1 \
  "$(printf '%s' "$OUT_ORPHAN" | jq '.allow | length - 1')"
assert_not_contains "and its text is not smuggled into the real entry" \
  "$(printf '%s' "$OUT_ORPHAN" | jq -r '.allow[1]')" "orphaned line"

NOSECTION=$(
  cat <<'EOF'
label Sectionless
covered something
EOF
)
rc=0
OUT_NOSECTION=$(draft "$NOSECTION") || rc=$?
assert_exit "a sectionless entry does not crash the drafter" 0 "$rc"
assert_eq "and yields an empty object rather than a guessed section" "{}" \
  "$(printf '%s' "$OUT_NOSECTION" | jq -c .)"

UNKNOWN=$(
  cat <<'EOF'
section bogus_section_name
label Skipped Entry
covered something
section allow
label Real Entry
covered something real
EOF
)
rc=0
ERR_UNKNOWN=$(printf '%s\n' "$UNKNOWN" | bash "$SCRIPT" 2>&1 >/dev/null) || rc=$?
assert_exit "an unknown section exits 2" 2 "$rc"
assert_contains "the section is named" "$ERR_UNKNOWN" "bogus_section_name"
assert_contains "and the four legal names are given" "$ERR_UNKNOWN" "environment, allow, soft_deny and hard_deny"
assert_contains "and the caller is told nothing was drafted" "$ERR_UNKNOWN" "Nothing was drafted"

OUT_UNKNOWN=$(printf '%s\n' "$UNKNOWN" | bash "$SCRIPT" 2>/dev/null)
assert_eq "no partial JSON is emitted" "" "$OUT_UNKNOWN"

MERGED=$(printf '%s\n' "$UNKNOWN" | bash "$SCRIPT" 2>&1 || true)
assert_not_contains "the merged stream carries no half-written JSON" "$MERGED" "{"

rc=0
printf 'section \nlabel X\ncovered y\n' | bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
assert_exit "an empty section name also exits 2" 2 "$rc"

rc=0
OUT_OK=$(printf 'section allow
label Real
covered z
' | bash "$SCRIPT") || rc=$?
assert_exit "a legal input still exits 0" 0 "$rc"
assert_contains "and drafts normally" "$OUT_OK" "Real:"

rc=0
err=$(printf '' | bash "$SCRIPT" 2>&1) || rc=$?
assert_exit "exit 2 on empty input" 2 "$rc"
assert_contains "the empty-input error says why" "$err" "nothing to draft"

rc=0
err=$(printf '   \n\n' | bash "$SCRIPT" 2>&1) || rc=$?
assert_exit "whitespace-only input is empty input" 2 "$rc"

rc=0
err=$(bash "$SCRIPT" --bogus </dev/null 2>&1) || rc=$?
assert_exit "exit 2 on an unknown argument" 2 "$rc"
assert_contains "the unknown argument is named" "$err" "unknown argument"

rc=0
help=$(bash "$SCRIPT" --help </dev/null 2>&1) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help states the no-write contract" "$help" "Writes nothing, anywhere, under any flag"
assert_contains "--help explains why \$defaults leads every section" "$help" "REPLACES the"

WATCH="$TEST_TMPDIR/watch"
mkdir -p "$WATCH/nested"
before="$(find "$WATCH" | LC_ALL=C sort)"
(cd "$WATCH" && printf '%s\n' "$ANSWERS" | bash "$SCRIPT" >/dev/null)
after="$(find "$WATCH" | LC_ALL=C sort)"
assert_eq "running the drafter changes nothing in its working directory" "$before" "$after"

FAKE_HOME="$TEST_TMPDIR/fake-home"
mkdir -p "$FAKE_HOME/.claude"
printf '{"permissions":{"allow":[]}}\n' >"$FAKE_HOME/.claude/settings.json"
home_before="$(cat "$FAKE_HOME/.claude/settings.json")"
# shellcheck disable=SC2016 # $1/$2 are the inner shell's positional parameters, passed after the _ placeholder; expanding them here would defeat the point
env -u CLAUDE_CONFIG_DIR HOME="$FAKE_HOME" bash -c 'printf "%s\n" "$1" | bash "$2" >/dev/null' _ "$ANSWERS" "$SCRIPT"
assert_eq "the user settings file is byte-identical afterwards" "$home_before" "$(cat "$FAKE_HOME/.claude/settings.json")"

report_and_exit
