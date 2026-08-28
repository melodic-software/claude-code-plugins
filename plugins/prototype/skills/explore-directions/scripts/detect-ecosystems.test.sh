#!/usr/bin/env bash
# Contract tests for this skill's detect-ecosystems.sh WRAPPER.
#
# The wrapper is not a second detector. It is the ${CLAUDE_SKILL_DIR}-addressable
# handle for the one at plugins/prototype/scripts/detect-ecosystems.sh, and it
# exists only because an `allowed-tools` Bash rule can substitute
# ${CLAUDE_SKILL_DIR} but leaves ${CLAUDE_PLUGIN_ROOT} a literal string, which
# makes any grant naming the plugin root inert. So the grant has to name a path
# under the skill's own directory, and this file is that path.
#
# Two ways that arrangement degrades, both of which look harmless in review:
#
#   1. Someone "removes the indirection" by pasting the detector's body in here.
#      The skill keeps working, and the two copies then drift apart silently.
#      The single-source assertions below fail that edit.
#   2. Someone tidies the header comment away, or swaps the self-locating
#      dirname walk for a ${CLAUDE_PLUGIN_ROOT} expansion, which is empty in the
#      Bash tool's environment. The grant goes inert and the preamble prints
#      nothing. The rationale and resolution assertions below fail that edit.
#
# The detector's own behavior is covered by its sibling suite at the plugin
# root; this suite proves delegation, not detection, plus one end-to-end smoke
# check that the delegation actually reaches a working detector.
#
# SC2016 is disabled file-wide on purpose, for the same reason the sibling
# allowed-tools-pairing suite disables it. Every single-quoted `${…}` below is a
# fixed string searched for VERBATIM in frontmatter or in the wrapper's source
# text. Letting the shell expand one would make the assertion match nothing.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SCRIPT_DIR/detect-ecosystems.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CANONICAL="$PLUGIN_ROOT/scripts/detect-ecosystems.sh"
SIBLING="$PLUGIN_ROOT/skills/pressure-test/scripts/detect-ecosystems.sh"
SKILL_MD="$(cd "$SCRIPT_DIR/.." && pwd)/SKILL.md"
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
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
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

# Executable lines only: the header comment is prose that differs on purpose
# between the two skill copies (each names the OTHER skill as the sibling).
body() { grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$1"; }

# --- 1. The file is reachable the way the grant reaches it ---------------------

if [[ -x "$WRAPPER" ]]; then
  pass "wrapper exists and is executable"
else
  fail "wrapper exists and is executable" "executable file" "$WRAPPER"
fi

assert_equals "wrapper sits at the \${CLAUDE_SKILL_DIR}-addressable path" \
  "$PLUGIN_ROOT/skills/explore-directions/scripts/detect-ecosystems.sh" "$WRAPPER"

# The grant in the skill body is what makes this path load-bearing. If the
# frontmatter ever stops naming it, this file is dead weight rather than a
# handle, and the pairing gate's own failure would be the first hint.
assert_contains "SKILL.md grants this exact skill-relative path" \
  "$(cat "$SKILL_MD")" 'Bash(${CLAUDE_SKILL_DIR}/scripts/detect-ecosystems.sh:*)'

# --- 2. It delegates rather than duplicates ------------------------------------

wrapper_body="$(body "$WRAPPER")"
assert_contains "wrapper hands off with exec" "$wrapper_body" "exec "
assert_contains "wrapper forwards its arguments" "$wrapper_body" '"$@"'
assert_contains "wrapper targets the plugin-root detector" "$wrapper_body" '/scripts/detect-ecosystems.sh'

# Single-sourcing. These are the detector's own internals; none of them may
# appear here, or there are two detectors to keep in step instead of one.
assert_not_contains "wrapper does not carry the marker list" "$wrapper_body" "pyproject.toml"
assert_not_contains "wrapper does not carry the detector's accumulator" "$wrapper_body" "found+=("
assert_not_contains "wrapper does not carry the empty answer" "$wrapper_body" "none detected"

# --- 3. It resolves the canonical script, and resolves it self-locatingly ------

assert_contains "wrapper walks up from its own BASH_SOURCE" "$wrapper_body" 'dirname "${BASH_SOURCE[0]}"'
assert_contains "wrapper walks the three levels to the plugin root" "$wrapper_body" '/../../..'

# ${CLAUDE_PLUGIN_ROOT} is not exported into the Bash tool's environment, so a
# shell expansion of it here yields an empty string and the exec target becomes
# /scripts/detect-ecosystems.sh. The name may appear in the rationale comment;
# it must never appear in an executable line.
assert_not_contains "no live \${CLAUDE_PLUGIN_ROOT} expansion in the body" "$wrapper_body" "CLAUDE_PLUGIN_ROOT"

if [[ -x "$CANONICAL" ]]; then
  pass "the resolved target exists and is executable"
else
  fail "the resolved target exists and is executable" "executable file" "$CANONICAL"
fi

# --- 4. The rationale survives -------------------------------------------------
# This comment is the only record of WHY a one-line exec file exists. A tidying
# pass that deletes it leaves the next reader with an obvious-looking deletion.

header="$(grep -e '^[[:space:]]*#' "$WRAPPER")"
assert_contains "rationale names the allowed-tools constraint" "$header" "allowed-tools"
assert_contains "rationale names the token that IS substituted" "$header" 'CLAUDE_SKILL_DIR'
assert_contains "rationale names the token that is NOT substituted" "$header" 'CLAUDE_PLUGIN_ROOT'
assert_contains "rationale records that the detector stays single-sourced" "$header" "single-source"
assert_contains "rationale explains the self-locating form" "$header" "not exported"

# --- 5. The two skill copies stay in lockstep -----------------------------------
# Same plugin, same handle, one detector. The prose headers differ by design
# (each names the other skill), so only the executable lines are compared.

if [[ -f "$SIBLING" ]]; then
  if diff <(body "$WRAPPER") <(body "$SIBLING") >/dev/null; then
    pass "the sibling skill's wrapper has a byte-identical body"
  else
    fail "the sibling skill's wrapper has a byte-identical body" \
      "identical executable lines" "$(diff <(body "$WRAPPER") <(body "$SIBLING") | tr '\n' ' ')"
  fi
else
  fail "the sibling skill's wrapper is present" "$SIBLING" "missing"
fi

# --- 6. Behavioral smoke: the delegation actually reaches a working detector ----
# Byte-for-byte against the canonical script on the same fixture, so the wrapper
# cannot pass by execing something that merely also exits 0.

MULTI="$TEST_TMPDIR/multi"
mkdir -p "$MULTI"
: >"$MULTI/package.json"
: >"$MULTI/go.mod"
: >"$MULTI/App.sln"

EMPTY="$TEST_TMPDIR/empty"
mkdir -p "$EMPTY"

for fixture in "$MULTI" "$EMPTY"; do
  label="$(basename "$fixture")"

  wrap_exit=0
  wrap_out="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$fixture" bash "$WRAPPER" 2>/dev/null)" || wrap_exit=$?
  canon_exit=0
  canon_out="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$fixture" bash "$CANONICAL" 2>/dev/null)" || canon_exit=$?

  assert_equals "$label: wrapper output matches the canonical detector" "$canon_out" "$wrap_out"
  assert_exit "$label: wrapper exit status matches the canonical detector" "$canon_exit" "$wrap_exit"
done

assert_equals "the multi fixture is a non-trivial comparison" \
  "$(printf '%s\n' App.sln package.json go.mod)" \
  "$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$MULTI" bash "$WRAPPER" 2>/dev/null)"

# Self-locating means the cwd is irrelevant. `/` is the harshest cwd available
# and is the one a preamble can genuinely land in.
root_out="$(cd / && CLAUDE_PROJECT_DIR="$MULTI" bash "$WRAPPER" 2>/dev/null)"
assert_equals "wrapper resolves its target from an unrelated cwd" \
  "$(printf '%s\n' App.sln package.json go.mod)" "$root_out"

# Direct invocation, no `bash` interpreter prefix: this is the form the paired
# grant permits, and the only one the skill body is allowed to use.
direct_out="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$MULTI" "$WRAPPER" 2>/dev/null)"
assert_equals "direct (non-interpreter-led) invocation works" \
  "$(printf '%s\n' App.sln package.json go.mod)" "$direct_out"

# Forwarded arguments reach a script that reads none. Inert, never fatal.
args_exit=0
args_out="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$MULTI" bash "$WRAPPER" --bogus extra 2>/dev/null)" || args_exit=$?
assert_equals "forwarded arguments do not change the answer" \
  "$(printf '%s\n' App.sln package.json go.mod)" "$args_out"
assert_exit "forwarded arguments do not fail the wrapper" 0 "$args_exit"

# --- Report ---------------------------------------------------------------------

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
echo "All explore-directions detect-ecosystems.sh wrapper checks passed."
