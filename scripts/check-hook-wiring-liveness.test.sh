#!/usr/bin/env bash
# Black-box contract test for check-hook-wiring-liveness.sh.
#
# Self-contained and cwd-independent: builds a throwaway .claude/settings.json
# + .claude/hooks/ tree, copies the checker next to it, and asserts on exit
# code + output. Mutates only its own mktemp dir. A green run on the current
# repo tree is not sufficient evidence the gate works — these fixtures prove
# it goes red on the #2959/#2960 failure class (an unwired hook script) and
# green when every non-test script is referenced by a hook command or env.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-hook-wiring-liveness.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/scripts" "$TMP/.claude/hooks"
cp "$SUT_SRC" "$TMP/scripts/check-hook-wiring-liveness.sh"
SUT="$TMP/scripts/check-hook-wiring-liveness.sh"

# Minimal settings: env-wired telemetry sink. Command-form and args-form
# wiring are asserted in their own cases; this fixture names no file
# outside .claude/hooks/.
write_settings() {
  cat >"$TMP/.claude/settings.json" <<'EOF'
{
  "env": {
    "HOOK_TELEMETRY_SINK": ".claude/hooks/hook-telemetry-sink.sh"
  },
  "hooks": {}
}
EOF
}

write_hook() {
  local name="$1"
  printf '#!/usr/bin/env bash\n# fixture %s\n' "$name" >"$TMP/.claude/hooks/$name"
}

run() { (cd "$TMP" && bash "$SUT" 2>&1); }

# --- 1. Happy path: env-wired sink, no extra scripts -> green. --------------
write_settings
write_hook hook-telemetry-sink.sh
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'is referenced by' <<<"$out"; then
  pass "happy path (env-wired sink only) passes"
else
  fail "happy path should pass (rc=$rc): $out"
fi

# --- 2. #2959's own failure class: pre-delete tree with the dead gate. ------
# The live specimen: pr-linkage-mcp-gate.sh checked in, settings.json does
# not name it (stripped in #2188, SessionStart-only restore in #2655).
write_hook pr-linkage-mcp-gate.sh
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNWIRED HOOK' <<<"$out" && grep -q 'pr-linkage-mcp-gate.sh' <<<"$out"; then
  pass "pre-delete replica (unwired pr-linkage-mcp-gate.sh) fails the gate"
else
  fail "pre-delete replica should fail naming the dead script (rc=$rc): $out"
fi
rm -f "$TMP/.claude/hooks/pr-linkage-mcp-gate.sh"

# --- 3. *.test.sh is out of scope even when unwired. ------------------------
write_hook hook-telemetry-sink.test.sh
write_hook pr-linkage-mcp-gate.test.sh
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  pass "*.test.sh siblings are ignored"
else
  fail "*.test.sh should not fail the gate (rc=$rc): $out"
fi
rm -f "$TMP/.claude/hooks/"*.test.sh

# --- 4. A command-wired hook (not just env) counts as referenced. -----------
write_hook extra-gate.sh
jq --arg cmd 'bash "$CLAUDE_PROJECT_DIR/.claude/hooks/extra-gate.sh"' \
  '.hooks.PreToolUse = [{"matcher":"Bash","hooks":[{"type":"command","command":$cmd}]}]' \
  "$TMP/.claude/settings.json" >"$TMP/.claude/settings.json.next"
mv "$TMP/.claude/settings.json.next" "$TMP/.claude/settings.json"
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  pass "a hook command string referencing extra-gate.sh passes"
else
  fail "command-wired extra-gate.sh should pass (rc=$rc): $out"
fi
rm -f "$TMP/.claude/hooks/extra-gate.sh"
write_settings

# --- 5. Exec-form args also count (command is the interpreter). -------------
write_hook extra-gate.sh
cat >"$TMP/.claude/settings.json" <<'EOF'
{
  "env": {
    "HOOK_TELEMETRY_SINK": ".claude/hooks/hook-telemetry-sink.sh"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash",
            "args": [".claude/hooks/extra-gate.sh"]
          }
        ]
      }
    ]
  }
}
EOF
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  pass "exec-form args referencing extra-gate.sh pass"
else
  fail "args-wired extra-gate.sh should pass (rc=$rc): $out"
fi
rm -f "$TMP/.claude/hooks/extra-gate.sh"
write_settings

# --- 6. A longer sibling name must not satisfy a shorter basename. ----------
# `not-gate.sh` in env would substring-match `gate.sh` under a raw grep -F.
write_hook gate.sh
write_hook not-gate.sh
jq '.env.HOOK_TELEMETRY_SINK = ".claude/hooks/not-gate.sh"' \
  "$TMP/.claude/settings.json" >"$TMP/.claude/settings.json.next"
mv "$TMP/.claude/settings.json.next" "$TMP/.claude/settings.json"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNWIRED HOOK' <<<"$out" && grep -q 'gate.sh' <<<"$out" && ! grep -q 'not-gate.sh' <<<"$out"; then
  pass "not-gate.sh wiring does not satisfy an unwired gate.sh"
else
  fail "bounded match should fail naming only gate.sh (rc=$rc): $out"
fi
rm -f "$TMP/.claude/hooks/gate.sh" "$TMP/.claude/hooks/not-gate.sh"
write_settings

# --- 7. Missing settings.json is a hard usage error, not a silent pass. -----
rm -f "$TMP/.claude/settings.json"
out="$(run)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'not found' <<<"$out"; then
  pass "missing settings.json exits 2"
else
  fail "missing settings.json should exit 2 (rc=$rc): $out"
fi
write_settings

# --- 8. Invalid settings.json fails closed. ---------------------------------
printf '{not json\n' >"$TMP/.claude/settings.json"
out="$(run)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'not valid JSON' <<<"$out"; then
  pass "invalid settings.json exits 2"
else
  fail "invalid settings.json should exit 2 (rc=$rc): $out"
fi
write_settings

# --- 9. Back to green after the dead script is gone. ------------------------
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  pass "gate returns to green once the dead script is deleted"
else
  fail "restored env-only tree should pass (rc=$rc): $out"
fi

# --- 10. Live tree pin: the checkout this test lives in must itself be green.
# After #2959's deletion that is the post-delete tree. Running the SUT in
# place (not the fixture copy) is the honesty proof the fixture cases cannot
# fake — if a new unwired hook lands beside this test, this assertion fails.
live_out="$( (cd "$SCRIPT_DIR/.." && bash "$SUT_SRC" 2>&1) )"
live_rc=$?
if [[ $live_rc -eq 0 ]]; then
  pass "live checkout is green (every repo-local hook script is wired)"
else
  fail "live checkout should pass after deleting the dead gate (rc=$live_rc): $live_out"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
