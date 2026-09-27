# shellcheck shell=bash
# Shared assertion primitives for this plugin's *.test.sh suites: the
# PASS/FAIL counters, the two text assertions, and the jq-free JSON assertion
# every audit-* suite runs its document through. Sourced, not executed; the
# *.test.sh glob a runner selects on never picks this file up.
#
# Each suite owns its own FAILED / CASE_NUM counters and sets them before
# sourcing this file. PASS lines go to stdout, FAIL lines to stderr, and the
# suite prints its own summary and exits non-zero when FAILED is above 0.
#
# Param order: (label, expected, actual) for assert_eq, (label, haystack,
# needle) for assert_contains, (label, json, python-expression) for
# assert_doc. A suite that wants a wider document excerpt in an assert_doc
# failure sets DOC_EXCERPT_BYTES before sourcing.
#
# Duplicated per plugin by design, not drift; see
# docs/conventions/shell-test-helpers/README.md at the repo root.

PY=python3
command -v python3 >/dev/null 2>&1 || PY=python
: "${DOC_EXCERPT_BYTES:=600}"

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$(printf '%s' "$2" | head -c 400)" ;;
  esac
}
# jq-free JSON assertions: a Python expression over the parsed document `d`.
assert_doc() {
  # assert_doc <name> <json> <python-expression>
  if printf '%s' "$2" | "$PY" -c "import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if ($3) else 1)" 2>/dev/null; then
    pass "$1"
  else
    fail "$1" "$3" "$(printf '%s' "$2" | head -c "$DOC_EXCERPT_BYTES")"
  fi
}

# cm_assert_tool_free_path <dir>: fill <dir> with a collector-free PATH and
# assert that none of the ladder's collectors still resolves there. The suite
# sources scripts/tool-free-path.sh before calling this.
cm_assert_tool_free_path() {
  local leftover
  cm_fill_tool_free_path "$1"
  leftover="$(cm_resolvable_ladder_collectors "$1" | sort -u | tr '\n' ' ')"
  leftover="${leftover% }"
  if [[ -z "$leftover" ]]; then
    pass "no ladder collector is resolvable on the tool-free PATH"
  else
    fail "no ladder collector is resolvable on the tool-free PATH" "none" "$leftover"
  fi
}
