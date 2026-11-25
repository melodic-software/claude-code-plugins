# shellcheck shell=bash
# shellcheck disable=SC2016

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

body() { grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$1"; }

run_from() {
  local cwd="$1" root="$2"
  shift 2
  (cd "$cwd" && CLAUDE_PROJECT_DIR="$root" "$@" 2>/dev/null)
}

detect_wrapper_contract() {
  local script_dir="$1" skill="$2" sibling_skill="$3"
  WRAPPER="$script_dir/detect-ecosystems.sh"
  PLUGIN_ROOT="$(cd "$script_dir/../../.." && pwd)"
  CANONICAL="$PLUGIN_ROOT/scripts/detect-ecosystems.sh"
  SIBLING="$PLUGIN_ROOT/skills/$sibling_skill/scripts/detect-ecosystems.sh"
  SKILL_MD="$(cd "$script_dir/.." && pwd)/SKILL.md"
  TEST_TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TEST_TMPDIR"' EXIT

  if [[ -x "$WRAPPER" ]]; then
    pass "wrapper exists and is executable"
  else
    fail "wrapper exists and is executable" "executable file" "$WRAPPER"
  fi

  assert_equals "wrapper sits at the \${CLAUDE_SKILL_DIR}-addressable path" \
    "$PLUGIN_ROOT/skills/$skill/scripts/detect-ecosystems.sh" "$WRAPPER"

  assert_contains "SKILL.md allowed-tools grants this exact skill-relative path" \
    "$(grep -e '^allowed-tools:' "$SKILL_MD")" '"Bash(${CLAUDE_SKILL_DIR}/scripts/detect-ecosystems.sh:*)"'
  assert_contains "SKILL.md runs the granted path directly, paired with the grant" \
    "$(cat "$SKILL_MD")" '!`${CLAUDE_SKILL_DIR}/scripts/detect-ecosystems.sh'

  local wrapper_body
  wrapper_body="$(body "$WRAPPER")"
  assert_contains "wrapper hands off with exec" "$wrapper_body" "exec "
  assert_contains "wrapper forwards its arguments" "$wrapper_body" '"$@"'
  assert_contains "wrapper targets the plugin-root detector" "$wrapper_body" '/scripts/detect-ecosystems.sh'

  assert_not_contains "wrapper does not carry the marker list" "$wrapper_body" "pyproject.toml"
  assert_not_contains "wrapper does not carry the detector's accumulator" "$wrapper_body" "found+=("
  assert_not_contains "wrapper does not carry the empty answer" "$wrapper_body" "none detected"

  assert_contains "wrapper walks up from its own BASH_SOURCE" "$wrapper_body" 'dirname "${BASH_SOURCE[0]}"'
  assert_contains "wrapper walks the three levels to the plugin root" "$wrapper_body" '/../../..'

  assert_not_contains "no live \${CLAUDE_PLUGIN_ROOT} expansion in the body" "$wrapper_body" "CLAUDE_PLUGIN_ROOT"

  if [[ -x "$CANONICAL" ]]; then
    pass "the resolved target exists and is executable"
  else
    fail "the resolved target exists and is executable" "executable file" "$CANONICAL"
  fi

  local rationale
  rationale="$(cat "$PLUGIN_ROOT/reference/skill-wrappers.md")"
  assert_contains "rationale names the allowed-tools constraint" "$rationale" "allowed-tools"
  assert_contains "rationale names the token grants use" "$rationale" 'CLAUDE_SKILL_DIR'
  assert_contains "rationale names the token grants avoid" "$rationale" 'CLAUDE_PLUGIN_ROOT'
  assert_contains "rationale records that the detector stays single-sourced" "$rationale" "single-source"
  assert_contains "rationale explains the self-locating form" "$rationale" "not exported"

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

  local multi="$TEST_TMPDIR/multi" empty="$TEST_TMPDIR/empty" multi_expected
  mkdir -p "$multi"
  : >"$multi/package.json"
  : >"$multi/go.mod"
  : >"$multi/App.sln"
  multi_expected="$(printf '%s\n' App.sln package.json go.mod)"
  mkdir -p "$empty"

  local fixture label wrap_exit wrap_out canon_exit canon_out
  for fixture in "$multi" "$empty"; do
    label="$(basename "$fixture")"

    wrap_exit=0
    wrap_out="$(run_from "$TEST_TMPDIR" "$fixture" bash "$WRAPPER")" || wrap_exit=$?
    canon_exit=0
    canon_out="$(run_from "$TEST_TMPDIR" "$fixture" bash "$CANONICAL")" || canon_exit=$?

    assert_equals "$label: wrapper output matches the canonical detector" "$canon_out" "$wrap_out"
    assert_exit "$label: wrapper exit status matches the canonical detector" "$canon_exit" "$wrap_exit"
  done

  assert_equals "the multi fixture is a non-trivial comparison" \
    "$multi_expected" \
    "$(run_from "$TEST_TMPDIR" "$multi" bash "$WRAPPER")"

  local root_out direct_out args_exit args_out
  root_out="$(run_from / "$multi" bash "$WRAPPER")"
  assert_equals "wrapper resolves its target from an unrelated cwd" \
    "$multi_expected" "$root_out"

  direct_out="$(run_from "$TEST_TMPDIR" "$multi" "$WRAPPER")"
  assert_equals "direct (non-interpreter-led) invocation works" \
    "$multi_expected" "$direct_out"

  args_exit=0
  args_out="$(run_from "$TEST_TMPDIR" "$multi" bash "$WRAPPER" --bogus extra)" || args_exit=$?
  assert_equals "forwarded arguments do not change the answer" \
    "$multi_expected" "$args_out"
  assert_exit "forwarded arguments do not fail the wrapper" 0 "$args_exit"

  printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
  [[ $FAILED -eq 0 ]] || exit 1
  echo "All $skill detect-ecosystems.sh wrapper checks passed."
}
