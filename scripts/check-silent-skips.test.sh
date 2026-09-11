#!/usr/bin/env bash
# Unit tests for check-silent-skips.sh. Builds a tiny synthetic plugins/ tree
# per scenario in a temp dir and invokes the script against it directly -- the
# script's own `cd "$(dirname "$0")/.."` makes this work unmodified: copy it
# to <fixture>/scripts/ and it scans <fixture>/plugins/*/hooks/*.sh.
# shellcheck disable=SC2016  # fixture bodies are literal hook-script code passed in single quotes; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-silent-skips.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
f=""

# --no-lib: this gate walks the fixture's own scripts/ tree for *.test.sh, so
# staged shared libraries would be extra files under the surface being scanned.
new_fixture() { # <out-var>
  fixture_tree::build "$1" --sut "$SCRIPT" --plugins --no-lib
}

hook_file() {
  local fixture="$1" plugin="$2" name="$3" content="$4"
  mkdir -p "$fixture/plugins/$plugin/hooks"
  printf '%s\n' "$content" >"$fixture/plugins/$plugin/hooks/$name"
}

script_test_file() {
  local fixture="$1" name="$2" content="$3"
  mkdir -p "$fixture/scripts"
  printf '%s\n' "$content" >"$fixture/scripts/$name"
}

run_check() (
  cd "$1" && bash scripts/check-silent-skips.sh
)

# --- same-line silent skip fails -------------------------------------------
new_fixture f
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
new_fixture f
hook_file "$f" alpha check.sh 'command -v pwsh >/dev/null 2>&1 || emit_skipped'
if run_check "$f" >/dev/null 2>&1; then
  fail "skip-named-helper guard should fail"
else
  ok "skip-named-helper guard (|| emit_skipped) fails"
fi
rm -rf "$f"

# --- same-line skip with annotation on the line above passes ---------------
new_fixture f
hook_file "$f" alpha check.sh '# silent-skip-ok: output discarded by design
command -v jq >/dev/null 2>&1 || exit 0'
if out="$(run_check "$f" 2>&1)"; then
  ok "annotated same-line skip passes"
else
  fail "annotated same-line skip should pass, got: $out"
fi
rm -rf "$f"

# --- annotation at the top of a multi-line comment block passes ------------
new_fixture f
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
new_fixture f
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
new_fixture f
hook_file "$f" alpha check.sh 'command -v jq >/dev/null 2>&1 || exit 0 # silent-skip-ok: sink is fire-and-forget'
if run_check "$f" >/dev/null 2>&1; then
  ok "same-line annotation passes"
else
  fail "same-line annotation should pass"
fi
rm -rf "$f"

# --- silent block skip fails -----------------------------------------------
new_fixture f
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

# --- block skip with a bare stderr notice FAILS (docs/conventions/
# hook-observability/: exit-0 stderr is never shown to the user or the
# agent, so a bare `>&2` write is not a sanctioned visibility signal) -------
new_fixture f
hook_file "$f" alpha check.sh 'if ! command -v jq >/dev/null 2>&1; then
  echo "alpha: jq not found — advisory disabled" >&2
  exit 0
fi'
if out="$(run_check "$f" 2>&1)"; then
  fail "block skip with bare stderr notice should fail, got success: $out"
else
  if echo "$out" | grep -q "silent block skip"; then
    ok "block skip with bare stderr notice fails"
  else
    fail "expected silent block skip message, got: $out"
  fi
fi
rm -rf "$f"

# --- block skip with a sanctioned notice call passes -----------------------
new_fixture f
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
new_fixture f
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
new_fixture f
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
new_fixture f
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
new_fixture f
hook_file "$f" alpha hook-utils.sh 'command -v jq >/dev/null 2>&1 || return 0'
hook_file "$f" alpha check.test.sh 'command -v jq >/dev/null 2>&1 || exit 0'
if out="$(run_check "$f" 2>&1)"; then
  ok "hook-utils.sh and *.test.sh are excluded from the scan"
else
  fail "excluded files should not be scanned, got: $out"
fi
rm -rf "$f"

# --- scripts/*.test.sh: ok "skip ..." scored as PASS fails (#2807) ---------
new_fixture f
script_test_file "$f" demo.test.sh 'ok "skip historical proof (deadbeef not in this clone)"'
if out="$(run_check "$f" 2>&1)"; then
  fail "ok skip-scored-as-pass should fail, got success: $out"
else
  if echo "$out" | grep -q "SILENT SKIP: scripts/demo.test.sh:1" &&
    echo "$out" | grep -q "skip scored as PASS"; then
    ok "scripts/*.test.sh ok \"skip ...\" fails with file:line"
  else
    fail "expected SILENT SKIP skip-scored-as-pass, got: $out"
  fi
fi
rm -rf "$f"

# --- scripts/*.test.sh: inline then ok "skip ..." also fails ----------------
new_fixture f
script_test_file "$f" demo.test.sh 'if anchor_missing; then ok "skip historical proof"; fi'
if out="$(run_check "$f" 2>&1)"; then
  fail "inline then ok skip should fail, got success: $out"
else
  if echo "$out" | grep -q "SILENT SKIP: scripts/demo.test.sh:1" &&
    echo "$out" | grep -q "skip scored as PASS"; then
    ok "inline then ok \"skip ...\" fails with file:line"
  else
    fail "expected SILENT SKIP for inline then ok skip, got: $out"
  fi
fi
rm -rf "$f"

# --- scripts/*.test.sh: annotated ok "skip ..." passes ---------------------
new_fixture f
script_test_file "$f" demo.test.sh "$(printf '%s\n' \
  '# silent-skip-ok: shallow clone lacks the historical anchor' \
  'ok "skip historical proof (deadbeef not in this clone)"')"
if out="$(run_check "$f" 2>&1)"; then
  ok "annotated scripts/*.test.sh ok \"skip ...\" passes"
else
  fail "annotated ok skip should pass, got: $out"
fi
rm -rf "$f"

# --- scripts/*.test.sh: same-line annotation passes ------------------------
new_fixture f
script_test_file "$f" demo.test.sh 'ok "skip historical proof" # silent-skip-ok: declared soft path'
if run_check "$f" >/dev/null 2>&1; then
  ok "same-line silent-skip-ok on ok \"skip ...\" passes"
else
  fail "same-line annotation on ok skip should pass"
fi
rm -rf "$f"

# --- ok messages that merely mention skip are not flagged ------------------
new_fixture f
script_test_file "$f" demo.test.sh "$(printf '%s\n' \
  'ok "skip-named-helper guard (|| emit_skipped) fails"' \
  'ok "same-line silent skip fails with file:line"' \
  'ok "repository baseline passes --check"')"
if out="$(run_check "$f" 2>&1)"; then
  ok "ok messages that mention skip without scoring a skip pass"
else
  fail "non skip-scored ok messages should pass, got: $out"
fi
rm -rf "$f"

# --- an empty plugins tree passes ------------------------------------------
new_fixture f
if run_check "$f" >/dev/null 2>&1; then
  ok "empty tree passes"
else
  fail "empty tree should pass"
fi
rm -rf "$f"

test_harness::report
