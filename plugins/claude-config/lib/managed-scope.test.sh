#!/usr/bin/env bash
# Regression tests for lib/managed-scope.sh — the per-OS managed-policy surface
# enumeration shared by claude-config's audit skills and claude-memory's scope
# report.
#
# The library contract this protects is side-effect freedom: callers source it,
# so a stray top-level command, output, or `exit` would run inside — and could
# terminate — an unrelated script.
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/managed-scope.sh"

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
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}

# --- Side-effect freedom -----------------------------------------------------
rc=0
bash -n "$LIB" || rc=$?
assert_eq "parses under bash -n" "0" "$rc"

# Sourcing must produce no output on either stream and must not exit the shell.
# `echo SURVIVED` after the source is the exit probe: a top-level `exit` in the
# library would swallow it.
out=$(bash -c "source '$LIB' >/dev/null 2>&1; echo SURVIVED" 2>&1)
assert_eq "sourcing does not exit the caller" "SURVIVED" "$out"
noise=$(bash -c "source '$LIB'" 2>&1)
assert_eq "sourcing writes nothing to stdout or stderr" "" "$noise"

# --- Path resolution ---------------------------------------------------------
assert_eq "macOS base file" \
  "/Library/Application Support/ClaudeCode/managed-settings.json" \
  "$(OSTYPE=darwin23 bash -c "source '$LIB'; mscope::base_file")"
assert_eq "Linux base file" \
  "/etc/claude-code/managed-settings.json" \
  "$(OSTYPE=linux-gnu bash -c "source '$LIB'; mscope::base_file")"
assert_contains "Windows base file resolves through PROGRAMFILES" \
  "$(OSTYPE=msys PROGRAMFILES='X:\PF' bash -c "source '$LIB'; mscope::base_file")" \
  'X:\PF\ClaudeCode\managed-settings.json'

# The legacy Windows location is unsupported since v2.1.75; probing it would
# report policy that is not in force.
assert_eq "legacy ProgramData path never emitted" "" \
  "$(OSTYPE=msys bash -c "source '$LIB'; mscope::base_file" | grep -i 'ProgramData' || true)"

# --- Drop-in directory sits beside the base, override and all ----------------
assert_eq "Linux drop-in dir" \
  "/etc/claude-code/managed-settings.d" \
  "$(OSTYPE=linux-gnu bash -c "source '$LIB'; mscope::dropin_dir")"
assert_eq "override relocates the base file verbatim" \
  "/tmp/fixture/managed-settings.json" \
  "$(bash -c "source '$LIB'; mscope::base_file /tmp/fixture/managed-settings.json")"
assert_eq "override relocates the drop-in dir with it" \
  "/tmp/fixture/managed-settings.d" \
  "$(bash -c "source '$LIB'; mscope::dropin_dir /tmp/fixture/managed-settings.json")"

# --- Non-file surfaces, emitted only where they exist -------------------------
win_keys="$(OSTYPE=msys bash -c "source '$LIB'; mscope::registry_keys")"
# portability-ok: the `\S` below are literal first characters of SOFTWARE in
# single-quoted Windows registry paths, not GNU regex escapes. The assertions are
# shell string comparisons; no regex engine sees these values.
assert_contains "Windows emits the admin-level policy key" "$win_keys" 'HKLM\SOFTWARE\Policies\ClaudeCode'
assert_contains "Windows emits the user-level policy key" "$win_keys" 'HKCU\SOFTWARE\Policies\ClaudeCode' # portability-ok: Windows registry path string in a test fixture, not a regex construct
assert_eq "HKLM is listed first (HKCU is lowest policy priority)" \
  'HKLM\SOFTWARE\Policies\ClaudeCode' "$(printf '%s\n' "$win_keys" | head -1)" # portability-ok: Windows registry path string in a test fixture, not a regex construct
assert_eq "no registry keys off Windows" "" \
  "$(OSTYPE=linux-gnu bash -c "source '$LIB'; mscope::registry_keys")"
assert_eq "macOS preferences domain" "com.anthropic.claudecode" \
  "$(OSTYPE=darwin23 bash -c "source '$LIB'; mscope::plist_domain")"
assert_eq "no preferences domain off macOS" "" \
  "$(OSTYPE=linux-gnu bash -c "source '$LIB'; mscope::plist_domain")"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
