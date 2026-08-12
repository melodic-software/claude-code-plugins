#!/usr/bin/env bash
# Unit tests for check-discriminating-test-skips.sh and the runtime
# fail_discriminating_skip contract. Builds a tiny synthetic plugins/ tree per
# scenario in a temp dir and invokes the gate against it directly — the script's
# own `cd "$(dirname "$0")/.."` makes this work unmodified: copy it to
# <fixture>/scripts/ and it scans <fixture>/plugins/**/*.test.sh.
# shellcheck disable=SC2016  # fixture bodies are literal test code in single quotes
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
SCRIPT="$SELF_DIR/check-discriminating-test-skips.sh"
HELPERS="$REPO_ROOT/plugins/source-control/scripts/test-helpers.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts" "$dir/plugins/alpha/skills/demo/scripts"
  cp "$SCRIPT" "$dir/scripts/check-discriminating-test-skips.sh"
  chmod +x "$dir/scripts/check-discriminating-test-skips.sh"
  printf '%s' "$dir"
}

# test_file <fixture> <relative-path-under-plugins> <content>
test_file() {
  local fixture="$1" rel="$2" content="$3"
  mkdir -p "$fixture/plugins/$(dirname "$rel")"
  printf '%s\n' "$content" >"$fixture/plugins/$rel"
}

run_check() (
  cd "$1" && bash scripts/check-discriminating-test-skips.sh
)

# --- copy-pairing skip_case fails the static gate ---------------------------
f="$(new_fixture)"
test_file "$f" alpha/skills/demo/scripts/demo.test.sh \
  'if [[ "$x" == "1" ]]; then :; else skip_case "this git did not pair the fixture as a copy"; fi'
if out="$(run_check "$f" 2>&1)"; then
  fail "copy-pairing skip_case should fail the gate, got success: $out"
else
  if echo "$out" | grep -q "DISCRIMINATING TEST SKIP: plugins/alpha/skills/demo/scripts/demo.test.sh:"; then
    ok "copy-pairing skip_case fails the static gate with file:line"
  else
    fail "expected DISCRIMINATING TEST SKIP with file:line, got: $out"
  fi
fi
rm -rf "$f"

# --- fail_discriminating_skip is not flagged --------------------------------
f="$(new_fixture)"
test_file "$f" alpha/skills/demo/scripts/demo.test.sh \
  'if [[ "$x" == "1" ]]; then :; else fail_discriminating_skip "unpaired"; fi'
if out="$(run_check "$f" 2>&1)"; then
  ok "fail_discriminating_skip passes the static gate"
else
  fail "fail_discriminating_skip should pass, got: $out"
fi
rm -rf "$f"

# --- annotated skip_case passes ---------------------------------------------
f="$(new_fixture)"
test_file "$f" alpha/skills/demo/scripts/demo.test.sh \
  '# discriminating-skip-ok: synthetic exemption fixture
skip_case "this git did not pair the fixture as a copy"'
if out="$(run_check "$f" 2>&1)"; then
  ok "annotated discriminating skip_case passes"
else
  fail "annotated skip_case should pass, got: $out"
fi
rm -rf "$f"

# --- runtime: fail_discriminating_skip fails the suite with marker -----------
tmp_test="$(mktemp --suffix=.test.sh)"
cat >"$tmp_test" <<EOF
#!/usr/bin/env bash
set -uo pipefail
FAILED=0
CASE_NUM=0
SKIP_CASES=0
DISCRIMINATING_SKIP_CASES=0
unset _TESTS_LIB_LOADED
# shellcheck source=/dev/null
source "$HELPERS"
fail_discriminating_skip "synthetic: git diff --cached --name-status has 0 C record(s), expected 1"
printf '\n%d case(s), %d failure(s), %d optional skip(s), %d discriminating skip(s)\n' \\
  "\$CASE_NUM" "\$FAILED" "\$SKIP_CASES" "\$DISCRIMINATING_SKIP_CASES"
[[ \$FAILED -eq 0 ]] || exit 1
EOF
chmod +x "$tmp_test"
if out="$(bash "$tmp_test" 2>&1)"; then
  fail "fail_discriminating_skip should fail the suite, got success: $out"
elif echo "$out" | grep -q '^DISCRIMINATING SKIP:'; then
  ok "fail_discriminating_skip fails the suite with DISCRIMINATING SKIP marker"
else
  fail "expected DISCRIMINATING SKIP marker, got: $out"
fi
rm -f "$tmp_test"

# --- runtime: optional skip_case still passes --------------------------------
tmp_test="$(mktemp --suffix=.test.sh)"
cat >"$tmp_test" <<EOF
#!/usr/bin/env bash
set -uo pipefail
FAILED=0
CASE_NUM=0
SKIP_CASES=0
DISCRIMINATING_SKIP_CASES=0
unset _TESTS_LIB_LOADED
# shellcheck source=/dev/null
source "$HELPERS"
skip_case "symlinks unsupported on this platform"
printf '\n%d case(s), %d failure(s), %d optional skip(s), %d discriminating skip(s)\n' \\
  "\$CASE_NUM" "\$FAILED" "\$SKIP_CASES" "\$DISCRIMINATING_SKIP_CASES"
[[ \$FAILED -eq 0 ]] || exit 1
EOF
chmod +x "$tmp_test"
if out="$(bash "$tmp_test" 2>&1)"; then
  if echo "$out" | grep -q '^SKIP:' && ! echo "$out" | grep -q '^DISCRIMINATING SKIP:'; then
    ok "optional skip_case still passes the suite"
  else
    fail "optional skip_case output unexpected: $out"
  fi
else
  fail "optional skip_case should pass, got: $out"
fi
rm -f "$tmp_test"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
