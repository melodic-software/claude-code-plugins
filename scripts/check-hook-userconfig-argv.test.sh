#!/usr/bin/env bash
# Unit tests for check-hook-userconfig-argv.sh. Builds a tiny synthetic
# plugins/ tree per scenario in a temp dir and invokes the script against it
# directly -- the script's own `cd "$(dirname "$0")/.."` makes this work
# unmodified: copy it to <fixture>/scripts/ and it scans <fixture>/plugins/.
# shellcheck disable=SC2016  # fixture bodies are literal JSON with ${user_config.*} tokens; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-hook-userconfig-argv.sh"

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
  cp "$SCRIPT" "$dir/scripts/check-hook-userconfig-argv.sh"
  chmod +x "$dir/scripts/check-hook-userconfig-argv.sh"
  printf '%s' "$dir"
}

# plugin_file <fixture> <plugin> <relpath> <content>
plugin_file() {
  local fixture="$1" plugin="$2" rel="$3" content="$4"
  mkdir -p "$fixture/plugins/$plugin/$(dirname "$rel")"
  printf '%s\n' "$content" >"$fixture/plugins/$plugin/$rel"
}

run_check() (
  cd "$1" && bash scripts/check-hook-userconfig-argv.sh
)

BARE_HOOK='{
  "hooks": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh",
          "args": ["--enabled", "${user_config.some_toggle}"]
        }
      ]
    }
  ]
}'

CLEAN_HOOK='{
  "hooks": [
    {
      "matcher": "Bash",
      "hooks": [
        { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh" }
      ]
    }
  ]
}'

# --- bare token in default hooks/hooks.json fails ---------------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json "$BARE_HOOK"
if out="$(run_check "$f" 2>&1)"; then
  fail "bare token in hooks/hooks.json should fail, got success: $out"
else
  if echo "$out" | grep -q 'USERCONFIG ARGV: plugins/alpha/hooks/hooks.json:'; then
    ok "bare token in default hooks.json fails with file:line"
  else
    fail "expected USERCONFIG ARGV with file:line, got: $out"
  fi
fi
rm -rf "$f"

# --- clean hooks.json passes ------------------------------------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json "$CLEAN_HOOK"
if out="$(run_check "$f" 2>&1)"; then
  ok "clean hooks.json passes"
else
  fail "clean hooks.json should pass, got: $out"
fi
rm -rf "$f"

# --- token in an MCP config is out of scope ---------------------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json "$CLEAN_HOOK"
plugin_file "$f" alpha .mcp.json '{"mcpServers":{"svc":{"env":{"TOKEN":"${user_config.api_token}"}}}}'
if out="$(run_check "$f" 2>&1)"; then
  ok "token in MCP config stays out of scope"
else
  fail "MCP config token should not be flagged, got: $out"
fi
rm -rf "$f"

# --- manifest string-path hook config with token fails ----------------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":"./config/extra-hooks.json"}'
plugin_file "$f" alpha config/extra-hooks.json "$BARE_HOOK"
if out="$(run_check "$f" 2>&1)"; then
  fail "manifest-pointed hook file with token should fail, got success: $out"
else
  if echo "$out" | grep -q 'USERCONFIG ARGV: plugins/alpha/config/extra-hooks.json:'; then
    ok "manifest string-path hook config fails"
  else
    fail "expected flag on manifest-pointed file, got: $out"
  fi
fi
rm -rf "$f"

# --- manifest array of hook paths: token in one element fails ---------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":["./hooks/hooks.json","./config/extra-hooks.json"]}'
plugin_file "$f" alpha hooks/hooks.json "$CLEAN_HOOK"
plugin_file "$f" alpha config/extra-hooks.json "$BARE_HOOK"
if run_check "$f" >/dev/null 2>&1; then
  fail "token in one of the manifest array paths should fail"
else
  ok "manifest array hook config fails on the offending element"
fi
rm -rf "$f"

# --- inline manifest hooks object with token fails --------------------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":{"hooks":[{"matcher":"Bash","hooks":[{"type":"command","command":"x","args":["${user_config.k}"]}]}]}}'
if out="$(run_check "$f" 2>&1)"; then
  fail "inline manifest hooks object with token should fail, got success: $out"
else
  if echo "$out" | grep -q 'USERCONFIG ARGV: plugins/alpha/.claude-plugin/plugin.json:inline hooks object'; then
    ok "inline manifest hooks object fails"
  else
    fail "expected inline-object flag, got: $out"
  fi
fi
rm -rf "$f"

# --- token elsewhere in the manifest (not hooks) passes ---------------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","mcpServers":{"svc":{"env":{"T":"${user_config.api_token}"}}},"hooks":{"hooks":[]}}'
if out="$(run_check "$f" 2>&1)"; then
  ok "token in manifest outside the hooks object passes"
else
  fail "non-hooks manifest token should pass, got: $out"
fi
rm -rf "$f"

# --- unreferenced hooks/*.json sibling is not scanned -----------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json "$CLEAN_HOOK"
plugin_file "$f" alpha hooks/unreferenced.json "$BARE_HOOK"
if out="$(run_check "$f" 2>&1)"; then
  ok "unreferenced hooks/*.json sibling stays unscanned"
else
  fail "unreferenced sibling should not be flagged, got: $out"
fi
rm -rf "$f"

# --- allowlisted file with token passes -------------------------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json "$BARE_HOOK"
printf '%s\n' 'plugins/alpha/hooks/hooks.json' >"$f/scripts/hook-userconfig-argv-allowlist.txt"
if out="$(run_check "$f" 2>&1)"; then
  ok "allowlisted hook config passes"
else
  fail "allowlisted hook config should pass, got: $out"
fi
rm -rf "$f"

# --- stale allowlist entry (file clean) fails -------------------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json "$CLEAN_HOOK"
printf '%s\n' 'plugins/alpha/hooks/hooks.json' >"$f/scripts/hook-userconfig-argv-allowlist.txt"
if out="$(run_check "$f" 2>&1)"; then
  fail "stale allowlist entry should fail, got success: $out"
else
  if echo "$out" | grep -q 'STALE ALLOWLIST:'; then
    ok "stale allowlist entry (clean file) fails"
  else
    fail "expected STALE ALLOWLIST, got: $out"
  fi
fi
rm -rf "$f"

# --- stale allowlist entry (file missing) fails -----------------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json "$CLEAN_HOOK"
printf '%s\n' 'plugins/gone/hooks/hooks.json' >"$f/scripts/hook-userconfig-argv-allowlist.txt"
if run_check "$f" >/dev/null 2>&1; then
  fail "allowlist entry for a missing file should fail"
else
  ok "stale allowlist entry (missing file) fails"
fi
rm -rf "$f"

# --- allowlist comments and blank lines are inert ---------------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json "$CLEAN_HOOK"
printf '%s\n' '# reserved for a ratified channel D adoption' '' >"$f/scripts/hook-userconfig-argv-allowlist.txt"
if out="$(run_check "$f" 2>&1)"; then
  ok "allowlist comments and blank lines are inert"
else
  fail "comment-only allowlist should pass, got: $out"
fi
rm -rf "$f"

# --- manifest with no hooks key passes --------------------------------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha"}'
plugin_file "$f" alpha hooks/hooks.json "$CLEAN_HOOK"
if out="$(run_check "$f" 2>&1)"; then
  ok "manifest without a hooks key passes"
else
  fail "manifest without a hooks key should pass, got: $out"
fi
rm -rf "$f"

# --- out-of-tree manifest hooks path is skipped, visibly --------------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":"../../outside.json"}'
printf '%s\n' "$BARE_HOOK" >"$f/outside.json"
if out="$(run_check "$f" 2>&1)"; then
  if echo "$out" | grep -q 'skipping out-of-tree hooks path'; then
    ok "out-of-tree manifest hooks path is skipped with a visible notice"
  else
    fail "expected visible out-of-tree skip notice, got: $out"
  fi
else
  fail "out-of-tree path should be skipped (pass), got: $out"
fi
rm -rf "$f"

# --- default and manifest-pointed configs both flagged ----------------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":"./config/extra-hooks.json"}'
plugin_file "$f" alpha hooks/hooks.json "$BARE_HOOK"
plugin_file "$f" alpha config/extra-hooks.json "$BARE_HOOK"
if out="$(run_check "$f" 2>&1)"; then
  fail "composite (default + manifest-pointed) should fail, got success: $out"
else
  if echo "$out" | grep -q 'USERCONFIG ARGV: plugins/alpha/hooks/hooks.json:' &&
    echo "$out" | grep -q 'USERCONFIG ARGV: plugins/alpha/config/extra-hooks.json:'; then
    ok "composite case flags both the default and the manifest-pointed config"
  else
    fail "expected both files flagged, got: $out"
  fi
fi
rm -rf "$f"

# --- unparsable manifest does not crash the gate ----------------------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{not json'
plugin_file "$f" alpha hooks/hooks.json "$CLEAN_HOOK"
if out="$(run_check "$f" 2>&1)"; then
  ok "unparsable manifest is skipped (manifest validity has its own gate)"
else
  fail "unparsable manifest should not fail this gate, got: $out"
fi
rm -rf "$f"

echo
echo "passed: $PASS, failed: $FAIL"
((FAIL == 0)) || exit 1
