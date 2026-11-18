# shellcheck shell=bash

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
assert_doc() {
  if printf '%s' "$2" | "$PY" -c "import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if ($3) else 1)" 2>/dev/null; then
    pass "$1"
  else
    fail "$1" "$3" "$(printf '%s' "$2" | head -c "$DOC_EXCERPT_BYTES")"
  fi
}

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
