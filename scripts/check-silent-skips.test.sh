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

new_fixture() { # <out-var>
  local -n _nf_out="$1"
  fixture_tree::build "$1" --sut "$SCRIPT" --plugins
  : >"$_nf_out/scripts/silent-skip-exemptions.txt"
}

exempt() {
  printf '%s\n' "$2" >>"$1/scripts/silent-skip-exemptions.txt"
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
  if grep -q "SILENT SKIP: plugins/alpha/hooks/check.sh:1" <<<"$out"; then
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

new_fixture f
hook_file "$f" alpha check.sh '# silent-skip-ok: output discarded by design
command -v jq >/dev/null 2>&1 || exit 0'
if out="$(run_check "$f" 2>&1)"; then
  fail "a silent-skip-ok comment above a guard must not exempt it, got success: $out"
else
  if grep -q "SILENT SKIP: plugins/alpha/hooks/check.sh:2" <<<"$out"; then
    ok "a silent-skip-ok comment above a guard does not exempt it"
  else
    fail "expected SILENT SKIP at check.sh:2, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
hook_file "$f" alpha check.sh '# silent-skip-ok: fire-and-forget sink — output discarded by the producer,
# so no notice channel exists here.
command -v jq >/dev/null 2>&1 || exit 0'
if run_check "$f" >/dev/null 2>&1; then
  fail "a silent-skip-ok comment block must not exempt the guard below it"
else
  ok "a silent-skip-ok comment block does not exempt the guard below it"
fi
rm -rf "$f"

new_fixture f
hook_file "$f" alpha check.sh '# silent-skip-ok: covers only the next guard
command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
command -v gh >/dev/null 2>&1 || exit 0'
exempt "$f" 'plugins/alpha/hooks/check.sh jq  output discarded by design'
if out="$(run_check "$f" 2>&1)"; then
  fail "an entry for jq must not exempt the gh guard, got success: $out"
else
  if grep -q "check.sh:4" <<<"$out" && ! grep -q "check.sh:2" <<<"$out"; then
    ok "an entry exempts only the guard on its own tool"
  else
    fail "expected only line 4 flagged, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
hook_file "$f" alpha check.sh 'command -v jq >/dev/null 2>&1 || exit 0 # silent-skip-ok: sink is fire-and-forget'
if run_check "$f" >/dev/null 2>&1; then
  fail "a same-line silent-skip-ok comment must not exempt the guard"
else
  ok "a same-line silent-skip-ok comment does not exempt the guard"
fi
rm -rf "$f"

new_fixture f
hook_file "$f" alpha check.sh 'INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0'
exempt "$f" 'plugins/alpha/hooks/check.sh jq  output discarded by design'
if out="$(run_check "$f" 2>&1)"; then
  ok "a same-line guard listed in the exemption file passes"
else
  fail "a listed same-line guard should pass, got: $out"
fi
rm -rf "$f"

new_fixture f
hook_file "$f" alpha check.sh 'command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0'
exempt "$f" 'plugins/alpha/hooks/check.sh jq  output discarded by design'
if out="$(run_check "$f" 2>&1)"; then
  fail "an entry must not exempt a second guard on its tool, got success: $out"
else
  if grep -q "SILENT SKIP: plugins/alpha/hooks/check.sh:3" <<<"$out" && ! grep -q "check.sh:1:" <<<"$out"; then
    ok "an entry exempts one guard; a second guard on its tool fails"
  else
    fail "expected only check.sh:3 flagged, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
hook_file "$f" alpha check.sh 'if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi'
exempt "$f" 'plugins/alpha/hooks/check.sh jq  not-applicable classification, CI is the gate'
if out="$(run_check "$f" 2>&1)"; then
  ok "a block guard listed in the exemption file passes"
else
  fail "a listed block guard should pass, got: $out"
fi
rm -rf "$f"

new_fixture f
hook_file "$f" alpha check.sh 'command -v jq >/dev/null 2>&1 || exit 0'
hook_file "$f" beta check.sh 'command -v jq >/dev/null 2>&1 || exit 0'
exempt "$f" 'plugins/alpha/hooks/check.sh jq  output discarded by design'
if out="$(run_check "$f" 2>&1)"; then
  fail "an entry for one file must not exempt another, got success: $out"
else
  if grep -q "SILENT SKIP: plugins/beta/hooks/check.sh:1" <<<"$out" &&
    ! grep -q "plugins/alpha" <<<"$out"; then
    ok "an unlisted guard fails while the listed one passes"
  else
    fail "expected only beta flagged, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
hook_file "$f" alpha check.sh 'INPUT=$(cat)'
exempt "$f" 'plugins/alpha/hooks/check.sh jq  output discarded by design'
if out="$(run_check "$f" 2>&1)"; then
  fail "a stale entry whose guard is gone should fail, got success: $out"
else
  if grep -q "STALE BASELINE: scripts/silent-skip-exemptions.txt: 'plugins/alpha/hooks/check.sh jq" <<<"$out"; then
    ok "a stale entry whose guard is gone fails"
  else
    fail "expected STALE BASELINE for the entry, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
hook_file "$f" alpha check.sh 'if ! command -v jq >/dev/null 2>&1; then
  hook::emit_skip_notice PostToolUse "alpha: jq missing"
  exit 0
fi'
exempt "$f" 'plugins/alpha/hooks/check.sh jq  output discarded by design'
if out="$(run_check "$f" 2>&1)"; then
  fail "an entry for a guard that is now visible should fail as stale, got success: $out"
else
  if grep -q "STALE BASELINE" <<<"$out" && ! grep -q "SILENT SKIP" <<<"$out"; then
    ok "an entry for a guard that is visible fails as stale"
  else
    fail "expected only STALE BASELINE, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
hook_file "$f" alpha check.sh 'command -v jq >/dev/null 2>&1 || exit 0'
exempt "$f" 'plugins/alpha/hooks/check.sh jq'
if out="$(run_check "$f" 2>&1)"; then
  fail "an entry with no reason should fail, got success: $out"
else
  if grep -q "no reason" <<<"$out"; then
    ok "an entry with no reason fails"
  else
    fail "expected a no-reason diagnostic, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
rm -f "$f/scripts/silent-skip-exemptions.txt"
out="$(run_check "$f" 2>&1)"
rc=$?
if ((rc == 2)); then
  ok "a missing exemption file fails closed with exit 2"
else
  fail "a missing exemption file should exit 2, got $rc: $out"
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
  if grep -q "silent block skip" <<<"$out"; then
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
  if grep -q "silent block skip" <<<"$out"; then
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

new_fixture f
hook_file "$f" alpha check.sh 'if ! command -v jq >/dev/null 2>&1; then
  # silent-skip-ok: not-applicable classification, CI is the gate
  exit 0
fi'
if run_check "$f" >/dev/null 2>&1; then
  fail "an in-block silent-skip-ok comment must not exempt the block"
else
  ok "an in-block silent-skip-ok comment does not exempt the block"
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
  if grep -q "SILENT SKIP: scripts/demo.test.sh:1" <<<"$out" &&
    grep -q "skip scored as PASS" <<<"$out"; then
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
  if grep -q "SILENT SKIP: scripts/demo.test.sh:1" <<<"$out" &&
    grep -q "skip scored as PASS" <<<"$out"; then
    ok "inline then ok \"skip ...\" fails with file:line"
  else
    fail "expected SILENT SKIP for inline then ok skip, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
script_test_file "$f" demo.test.sh "$(printf '%s\n' \
  '# silent-skip-ok: shallow clone lacks the historical anchor' \
  'ok "skip historical proof (deadbeef not in this clone)"')"
if run_check "$f" >/dev/null 2>&1; then
  fail "a silent-skip-ok comment must not exempt ok \"skip ...\""
else
  ok "a silent-skip-ok comment does not exempt scripts/*.test.sh ok \"skip ...\""
fi
rm -rf "$f"

new_fixture f
script_test_file "$f" demo.test.sh 'ok "skip historical proof" # silent-skip-ok: declared soft path'
if run_check "$f" >/dev/null 2>&1; then
  fail "a same-line silent-skip-ok comment must not exempt ok \"skip ...\""
else
  ok "a same-line silent-skip-ok comment does not exempt ok \"skip ...\""
fi
rm -rf "$f"

new_fixture f
script_test_file "$f" demo.test.sh "$(printf '%s\n' \
  'anchor_missing || return' \
  'ok "skip historical proof (deadbeef not in this clone)"')"
exempt "$f" 'scripts/demo.test.sh "skip historical proof (deadbeef not in this clone)"  shallow clone lacks the historical anchor'
if out="$(run_check "$f" 2>&1)"; then
  ok "a listed scripts/*.test.sh ok \"skip ...\" passes"
else
  fail "a listed ok skip should pass, got: $out"
fi
rm -rf "$f"

new_fixture f
script_test_file "$f" demo.test.sh 'ok "skip other proof"'
exempt "$f" 'scripts/demo.test.sh "skip historical proof"  shallow clone lacks the historical anchor'
if out="$(run_check "$f" 2>&1)"; then
  fail "an entry for another skip message must not exempt this one, got success: $out"
else
  if grep -q "SILENT SKIP: scripts/demo.test.sh:1" <<<"$out" && grep -q "STALE BASELINE" <<<"$out"; then
    ok "an ok \"skip ...\" entry matches its message exactly, and an unmatched one is stale"
  else
    fail "expected SILENT SKIP and STALE BASELINE, got: $out"
  fi
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
