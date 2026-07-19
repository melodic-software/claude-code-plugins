#!/usr/bin/env bash
# Unit tests for check-silent-skips.sh. Builds a tiny synthetic plugins/ tree
# per scenario in a temp dir and invokes the script against it directly -- the
# script's own `cd "$(dirname "$0")/.."` makes this work unmodified: copy it
# to <fixture>/scripts/ and it scans <fixture>/plugins/*/hooks/*.sh.
# shellcheck disable=SC2016  # fixture bodies are literal hook-script code passed in single quotes; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-silent-skips.sh"

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
  mkdir -p "$dir/scripts" "$dir/plugins"
  cp "$SCRIPT" "$dir/scripts/check-silent-skips.sh"
  chmod +x "$dir/scripts/check-silent-skips.sh"
  printf '%s' "$dir"
}

# hook_file <fixture> <plugin> <basename> <content>
hook_file() {
  local fixture="$1" plugin="$2" name="$3" content="$4"
  mkdir -p "$fixture/plugins/$plugin/hooks"
  printf '%s\n' "$content" >"$fixture/plugins/$plugin/hooks/$name"
}

run_check() (
  cd "$1" && bash scripts/check-silent-skips.sh
)

# --- same-line silent skip fails -------------------------------------------
f="$(new_fixture)"
hook_file "$f" alpha check.sh 'command -v jq >/dev/null 2>&1 || exit 0'
if out="$(run_check "$f" 2>&1)"; then
  fail "same-line silent skip should fail, got success: $out"
else
  if echo "$out" | grep -q "SILENT SKIP: plugins/alpha/hooks/check.sh:1"; then
    ok "same-line silent skip fails with file:line"
  else
    fail "expected SILENT SKIP with file:line, got: $out"
  fi
fi
rm -rf "$f"

# --- same-line skip via skip-named helper fails ----------------------------
f="$(new_fixture)"
hook_file "$f" alpha check.sh 'command -v pwsh >/dev/null 2>&1 || emit_skipped'
if run_check "$f" >/dev/null 2>&1; then
  fail "skip-named-helper guard should fail"
else
  ok "skip-named-helper guard (|| emit_skipped) fails"
fi
rm -rf "$f"

# --- same-line skip with annotation on the line above passes ---------------
f="$(new_fixture)"
hook_file "$f" alpha check.sh '# silent-skip-ok: output discarded by design
command -v jq >/dev/null 2>&1 || exit 0'
if out="$(run_check "$f" 2>&1)"; then
  ok "annotated same-line skip passes"
else
  fail "annotated same-line skip should pass, got: $out"
fi
rm -rf "$f"

# --- annotation at the top of a multi-line comment block passes ------------
f="$(new_fixture)"
hook_file "$f" alpha check.sh '# silent-skip-ok: fire-and-forget sink — output discarded by the producer,
# so no notice channel exists here.
command -v jq >/dev/null 2>&1 || exit 0'
if run_check "$f" >/dev/null 2>&1; then
  ok "annotation anywhere in the comment block above the guard passes"
else
  fail "multi-line comment-block annotation should pass"
fi
rm -rf "$f"

# --- an annotation does not leak past intervening code ---------------------
f="$(new_fixture)"
hook_file "$f" alpha check.sh '# silent-skip-ok: covers only the next guard
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
command -v gh >/dev/null 2>&1 || exit 0'
if out="$(run_check "$f" 2>&1)"; then
  fail "annotation should not sanction a later guard, got success: $out"
else
  if echo "$out" | grep -q "check.sh:4"; then
    ok "annotation does not leak past intervening code"
  else
    fail "expected only line 4 flagged, got: $out"
  fi
fi
rm -rf "$f"

# --- same-line skip with annotation on the same line passes ----------------
f="$(new_fixture)"
hook_file "$f" alpha check.sh 'command -v jq >/dev/null 2>&1 || exit 0 # silent-skip-ok: sink is fire-and-forget'
if run_check "$f" >/dev/null 2>&1; then
  ok "same-line annotation passes"
else
  fail "same-line annotation should pass"
fi
rm -rf "$f"

# --- silent block skip fails -----------------------------------------------
f="$(new_fixture)"
hook_file "$f" alpha check.sh 'if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi'
if out="$(run_check "$f" 2>&1)"; then
  fail "silent block skip should fail, got success: $out"
else
  if echo "$out" | grep -q "silent block skip"; then
    ok "silent block skip fails"
  else
    fail "expected silent block skip message, got: $out"
  fi
fi
rm -rf "$f"

# --- block skip with a stderr notice passes --------------------------------
f="$(new_fixture)"
hook_file "$f" alpha check.sh 'if ! command -v jq >/dev/null 2>&1; then
  echo "alpha: jq not found — advisory disabled" >&2
  exit 0
fi'
if run_check "$f" >/dev/null 2>&1; then
  ok "block skip with stderr notice passes"
else
  fail "block skip with stderr notice should pass"
fi
rm -rf "$f"

# --- block skip with a sanctioned notice call passes -----------------------
f="$(new_fixture)"
hook_file "$f" alpha check.sh 'if ! command -v actionlint >/dev/null 2>&1; then
  hook::emit_skip_notice PostToolUse "alpha: actionlint not found — lint skipped"
  exit 0
fi'
if run_check "$f" >/dev/null 2>&1; then
  ok "block skip with hook::emit_skip_notice passes"
else
  fail "block skip with hook::emit_skip_notice should pass"
fi
rm -rf "$f"

# --- block skip with an in-block annotation passes -------------------------
f="$(new_fixture)"
hook_file "$f" alpha check.sh 'if ! command -v jq >/dev/null 2>&1; then
  # silent-skip-ok: not-applicable classification, CI is the gate
  exit 0
fi'
if run_check "$f" >/dev/null 2>&1; then
  ok "block skip with in-block annotation passes"
else
  fail "block skip with in-block annotation should pass"
fi
rm -rf "$f"

# --- nested if inside the guard block is tracked to the right fi -----------
f="$(new_fixture)"
hook_file "$f" alpha check.sh 'if ! command -v jq >/dev/null 2>&1; then
  if [[ -n "${VERBOSE:-}" ]]; then
    true
  fi
  exit 0
fi'
if run_check "$f" >/dev/null 2>&1; then
  fail "nested-if silent block should still fail"
else
  ok "nested-if silent block still fails (fi matching is depth-aware)"
fi
rm -rf "$f"

# --- non-skip guards are never flagged -------------------------------------
f="$(new_fixture)"
hook_file "$f" alpha check.sh 'command -v cygpath >/dev/null 2>&1 || return 1
command -v "$bin" >/dev/null 2>&1 || continue
if command -v perl >/dev/null 2>&1; then
  true
fi'
if out="$(run_check "$f" 2>&1)"; then
  ok "return 1 / continue / positive-form guards never flagged"
else
  fail "non-skip guards should pass, got: $out"
fi
rm -rf "$f"

# --- hook-utils.sh copies and test files are excluded ----------------------
f="$(new_fixture)"
hook_file "$f" alpha hook-utils.sh 'command -v jq >/dev/null 2>&1 || return 0'
hook_file "$f" alpha check.test.sh 'command -v jq >/dev/null 2>&1 || exit 0'
if out="$(run_check "$f" 2>&1)"; then
  ok "hook-utils.sh and *.test.sh are excluded from the scan"
else
  fail "excluded files should not be scanned, got: $out"
fi
rm -rf "$f"

# --- an empty plugins tree passes ------------------------------------------
f="$(new_fixture)"
if run_check "$f" >/dev/null 2>&1; then
  ok "empty tree passes"
else
  fail "empty tree should pass"
fi
rm -rf "$f"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
