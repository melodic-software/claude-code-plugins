#!/usr/bin/env bash
# Regression tests for lib/permission-patterns.sh — the auto-mode drop
# vocabulary shared by audit-permission-grants' check P1 and
# audit-permission-state's entry diff.
#
# The classification behaviour is exercised in depth by the P1 detector's own
# suite. What is proved HERE is what only a second consumer needs: the file is
# safe to source, and its bodies are usable standalone without the detector.
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/permission-patterns.sh"

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
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}

# --- Side-effect freedom -----------------------------------------------------
rc=0
bash -n "$LIB" || rc=$?
assert_eq "parses under bash -n" "0" "$rc"

out=$(bash -c "source '$LIB' >/dev/null 2>&1; echo SURVIVED" 2>&1)
assert_eq "sourcing does not exit the caller" "SURVIVED" "$out"
noise=$(bash -c "source '$LIB'" 2>&1)
assert_eq "sourcing writes nothing to stdout or stderr" "" "$noise"

# --- The vocabulary is defined and usable standalone -------------------------
# shellcheck source=permission-patterns.sh
source "$LIB"
assert_eq "P1 body defined" "0" "$([[ -n "${CCPERM_P1_ERE:-}" ]] && echo 0 || echo 1)"
assert_eq "tool-token body defined" "0" "$([[ -n "${CCPERM_TOOL_TOKEN_ERE:-}" ]] && echo 0 || echo 1)"

matches() { printf '%s\n' "$1" | grep -qE "$CCPERM_P1_ERE" && echo yes || echo no; }

# One rule per documented drop class, and one narrow rule that must carry over.
assert_eq "blanket Bash(*) is a drop class" "yes" "$(matches 'Bash(*)')"
assert_eq "wildcarded interpreter is a drop class" "yes" "$(matches 'Bash(python*)')"
assert_eq "package-manager runner is a drop class" "yes" "$(matches 'Bash(npx *)')"
assert_eq "script-glob interpreter is a drop class" "yes" "$(matches 'Bash(*.py:*)')"
assert_eq "narrow rule carries over" "no" "$(matches 'Bash(npm test)')"
assert_eq "bare-name command rule carries over" "no" "$(matches 'Bash(node-gyp:*)')"

# The token grammar keeps a tool name inside another rule's payload from
# surfacing as its own token — the property whole-tool detection depends on.
tokens=$(printf '%s\n' 'Bash(echo Agent)' | grep -oE "$CCPERM_TOOL_TOKEN_ERE")
assert_eq "payload text is not a separate top-level token" "Bash(echo Agent)" "$tokens"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
