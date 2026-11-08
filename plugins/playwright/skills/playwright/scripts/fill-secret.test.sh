#!/usr/bin/env bash
# Tests for fill-secret.sh against a stub playwright-cli that echoes the fill
# text the way the real CLI does, so a leak shows up in the captured output.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/fill-secret.sh"
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
assert_eq() {
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

SENTINEL='SENTINEL-NOT-A-SECRET-42'
STUB_BIN="$TEST_TMPDIR/bin"
ARGS_FILE="$TEST_TMPDIR/args"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/playwright-cli" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_ARGS_FILE"
printf "### Ran Playwright code\nawait page.locator('#p').fill('%s');\n" "$4"
printf 'stderr copy: %s\n' "$4" >&2
exit "${STUB_EXIT:-0}"
EOF
chmod +x "$STUB_BIN/playwright-cli"

run() {
  rm -f "$ARGS_FILE"
  env -u SECRET_PW PATH="$STUB_BIN:$PATH" STUB_ARGS_FILE="$ARGS_FILE" "$@" 2>&1
}

# --- 1. Success: the stub gets the value, the output does not --------------------

out=$(run SECRET_PW="$SENTINEL" bash "$SCRIPT" flow e2 SECRET_PW)
assert_eq "success: exit 0" 0 "$?"
assert_not_contains "success: no secret in output" "$out" "$SENTINEL"
assert_contains "success: names the target and variable" "$out" "filled e2 from SECRET_PW"
assert_eq "success: stub received session, fill, target and value" \
  "$(printf '%s\n' -s=flow fill e2 "$SENTINEL")" "$(cat "$ARGS_FILE")"

# --- 2. --submit is forwarded ---------------------------------------------------

out=$(run SECRET_PW="$SENTINEL" bash "$SCRIPT" flow e2 SECRET_PW --submit)
assert_eq "--submit: exit 0" 0 "$?"
assert_not_contains "--submit: no secret in output" "$out" "$SENTINEL"
assert_eq "--submit forwarded as the last argument" "--submit" "$(tail -n 1 "$ARGS_FILE")"

# --- 3. Failure: exit status passes through, output stays secret-free -----------

out=$(run SECRET_PW="$SENTINEL" STUB_EXIT=3 bash "$SCRIPT" flow e2 SECRET_PW)
assert_eq "failure: playwright-cli exit status returned" 3 "$?"
assert_not_contains "failure: no secret in output" "$out" "$SENTINEL"
assert_contains "failure: reports the failure" "$out" "failed (exit 3)"

# --- 4. Unset or empty variable: refused before playwright-cli runs --------------

out=$(run SECRET_PW= bash "$SCRIPT" flow e2 SECRET_PW)
assert_eq "empty variable: exit 2" 2 "$?"
assert_contains "empty variable: names it" "$out" "SECRET_PW is unset or empty"
if [[ -e "$ARGS_FILE" ]]; then
  fail "empty variable: playwright-cli not run" "no call" "called"
else
  pass "empty variable: playwright-cli not run"
fi

out=$(run bash "$SCRIPT" flow e2 SECRET_PW)
assert_eq "unset variable: exit 2" 2 "$?"
assert_contains "unset variable: names it" "$out" "SECRET_PW is unset or empty"
if [[ -e "$ARGS_FILE" ]]; then
  fail "unset variable: playwright-cli not run" "no call" "called"
else
  pass "unset variable: playwright-cli not run"
fi

out=$(run SECRET_PW="$SENTINEL" bash "$SCRIPT" flow e2 target)
assert_eq "script-internal name: exit 2" 2 "$?"
if [[ -e "$ARGS_FILE" ]]; then
  fail "script-internal name: playwright-cli not run" "no call" "called"
else
  pass "script-internal name: playwright-cli not run"
fi

# --- 5. Usage errors ----------------------------------------------------------------

run bash "$SCRIPT" flow e2 >/dev/null
assert_eq "too few arguments: exit 2" 2 "$?"
run SECRET_PW="$SENTINEL" bash "$SCRIPT" flow e2 SECRET_PW --bogus >/dev/null
assert_eq "unknown fourth argument: exit 2" 2 "$?"
out=$(run bash "$SCRIPT" flow e2 'not-a-name')
assert_eq "invalid variable name: exit 2" 2 "$?"
assert_contains "invalid variable name: says so" "$out" "is not an environment variable name"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
