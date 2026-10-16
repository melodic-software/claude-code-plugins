#!/usr/bin/env bash
# Contract test for typos-format's Claude Code hook rows after spell-check
# findings moved to commit time: the hooks.json row set (no per-edit
# PostToolUse row and no digest reset; the SessionStart probe and node-notice rows;
# the opt-in Stop row), the prerequisites manifest, the SessionStart probe's
# kill-switch gate, and typos-format.sh's remaining entry points. The Stop
# row's behavior is typos-format-end-of-turn.test.sh; the pre-commit check is
# git-hooks/typos-check.test.sh.
# test-scope: plugins/typos-format/.claude-plugin/plugin.json plugins/typos-format/hooks/hooks.json plugins/typos-format/prerequisites.json

set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/typos-format.sh"
PLUGIN_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
HOOKS_JSON="$HOOK_DIR/hooks.json"

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
command -v jq >/dev/null 2>&1 || {
  echo "SKIP: jq not on PATH -- typos-format row tests skipped"
  exit 0
}

# --- The row set ------------------------------------------------------------------
if [[ "$(jq -c '.hooks | keys' "$HOOKS_JSON")" == '["SessionStart","Stop"]' ]]; then
  ok "hooks.json: no per-edit PostToolUse row; only SessionStart and Stop"
else
  fail "hooks.json: want events [SessionStart, Stop], got $(jq -c '.hooks | keys' "$HOOKS_JSON")"
fi
# SessionStart carries exactly two commands: the prerequisites probe behind the
# plugin kill switch and the node-notice row (pinned fleet-wide by
# scripts/node-notice-rows.test.sh). No row resets per-edit finding digests:
# nothing writes them now that findings arrive at commit time.
if jq -e --arg checker '${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs' --arg root '${CLAUDE_PLUGIN_ROOT}' \
  '([.hooks.SessionStart[].hooks[]] | length == 2) and ([.hooks.SessionStart[].hooks[] | select(.command == "node" and .args == [$checker, "probe", $root, "--run-if-unset-or-true", "TYPOS_FORMAT_ENABLED"])] | length == 1)' "$HOOKS_JSON" >/dev/null; then
  ok "hooks.json: two SessionStart commands, one the probe behind --run-if-unset-or-true TYPOS_FORMAT_ENABLED"
else
  fail "hooks.json: expected two SessionStart commands including the gated prerequisites probe"
fi
if [[ "$(jq '[.hooks[][] | select(.matcher == "compact|clear")] + [.. | strings | select(. == "--reset-digests")] | length' "$HOOKS_JSON")" == "0" ]]; then
  ok "hooks.json: no compact|clear row and no --reset-digests argument"
else
  fail "hooks.json: a compact|clear or --reset-digests row is still registered"
fi
if jq -e '([.hooks.Stop[].hooks[] | select(.command == "node" and .args == ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "--run-if-unset-or-true", "TYPOS_FORMAT_ENABLED", "--require-true", "TYPOS_FORMAT_END_OF_TURN", "${CLAUDE_PLUGIN_ROOT}/hooks/typos-format.sh", "--end-of-turn"])] | length == 1) and ([.hooks.Stop[].hooks[]] | length == 1)' "$HOOKS_JSON" >/dev/null; then
  ok "hooks.json: one Stop row runs --end-of-turn behind --require-true TYPOS_FORMAT_END_OF_TURN"
else
  fail "hooks.json: expected exactly one Stop row running --end-of-turn behind --require-true TYPOS_FORMAT_END_OF_TURN"
fi
if [[ "$(jq -c '.userConfig | keys' "$PLUGIN_ROOT/.claude-plugin/plugin.json")" == '["typos_format_enabled","typos_format_end_of_turn"]' ]]; then
  ok "plugin.json: the options are the kill switch and the end-of-turn opt-in"
else
  fail "plugin.json: unexpected options $(jq -c '.userConfig | keys' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
fi
if [[ "$(jq '.userConfig.typos_format_end_of_turn.default' "$PLUGIN_ROOT/.claude-plugin/plugin.json")" == false ]]; then
  ok "plugin.json: the end-of-turn check is off by default"
else
  fail "plugin.json: typos_format_end_of_turn must default to false"
fi

# --- The manifest lists the plugin's tools ------------------------------------------
MANIFEST="$PLUGIN_ROOT/prerequisites.json"
if jq -e '(.requires | map(.id)) == ["typos", "jq", "node"]' "$MANIFEST" >/dev/null 2>&1; then
  ok "manifest: declares exactly typos, jq and node"
else
  fail "manifest: expected tools typos, jq and node: $(cat "$MANIFEST" 2>/dev/null)"
fi
IFS=$'\t' read -r MF_NAME MF_CHECK MF_INSTALL < <(jq -r '.requires[0] | [.id, .check, (.install | to_entries[0].value)] | @tsv' "$MANIFEST")

# --- SessionStart probe honors typos_format_enabled -----------------------------------
# Runs the probe row as the harness spawns it: `node` with the row's args,
# ${CLAUDE_PLUGIN_ROOT} expanded, from an empty cwd, on a PATH that holds the
# system tools and no typos.
NODE_BIN="$(command -v node 2>/dev/null)"
if [[ -z "$NODE_BIN" ]]; then
  fail "probe-gate: node is not on PATH, and every hook row launches through node"
else
  PG_WORK="$(mktemp -d)"
  trap 'rm -rf "$PG_WORK"' EXIT
  mkdir -p "$PG_WORK/sysbin" "$PG_WORK/cwd"
  for dir in /usr/local/bin /usr/bin /bin; do
    for exe in "$dir"/*; do
      base="${exe##*/}"
      [[ -x "$exe" && "$base" != typos && ! -e "$PG_WORK/sysbin/$base" ]] || continue
      MSYS=winsymlinks:nativestrict ln -s "$exe" "$PG_WORK/sysbin/$base"
    done
  done
  PG_ARGS=()
  while IFS= read -r pg_arg; do
    # shellcheck disable=SC2016  # the placeholder is matched literally, as Claude Code substitutes it
    PG_ARGS+=("${pg_arg//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_ROOT}")
  done < <(jq -r '.hooks.SessionStart[0].hooks[0].args[]' "$HOOKS_JSON")

  run_probe() { # <value|__unset__>
    local v="$1"
    local -a opt=(env -u CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED)
    [[ "$v" == "__unset__" ]] || opt=(env "CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=$v")
    (cd "$PG_WORK/cwd" && printf '{"session_id":"s1"}' |
      "${opt[@]}" PATH="$PG_WORK/sysbin" CLAUDE_PLUGIN_DATA="$(mktemp -d "$PG_WORK/data.XXXXXX")" \
        "$NODE_BIN" "${PG_ARGS[@]}" 2>&1)
  }

  OUT_PG=$(run_probe false)
  RC_PG=$?
  if [[ $RC_PG -eq 0 && -z "$OUT_PG" ]]; then
    ok "probe-gate: typos_format_enabled=false -> exit 0 and no notice"
  else
    fail "probe-gate: typos_format_enabled=false should print nothing and exit 0 (rc=$RC_PG out=$OUT_PG)"
  fi
  for v in __unset__ true; do
    label="typos_format_enabled=$v"
    [[ "$v" == "__unset__" ]] && label="typos_format_enabled unset"
    OUT_PG=$(run_probe "$v")
    RC_PG=$?
    if [[ $RC_PG -eq 0 && "$OUT_PG" == *"$MF_NAME"* && "$OUT_PG" == *"$MF_CHECK"* && "$OUT_PG" == *"$MF_INSTALL"* ]]; then
      ok "probe-gate: $label -> notice names $MF_NAME, $MF_CHECK and the install line"
    else
      fail "probe-gate: $label should print the missing-typos notice (rc=$RC_PG out=$OUT_PG)"
    fi
  done
  # No remaining row needs jq, so a host without it hears nothing about jq.
  rm -f "$PG_WORK/sysbin/jq"
  OUT_PG=$(run_probe __unset__)
  if [[ "$OUT_PG" == *"$MF_NAME"* && "$OUT_PG" != *"jq not on"* ]]; then
    ok "probe-gate: a missing jq draws no notice"
  else
    fail "probe-gate: a missing jq should draw no notice (out=$OUT_PG)"
  fi
  rm -rf "${PG_WORK:?}"
fi

# --- typos-format.sh's remaining entry points -------------------------------------
out="$(printf '{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/x.md"}}' | bash "$HOOK" 2>&1)"
rc=$?
if [[ $rc -eq 0 && -z "$out" ]]; then
  ok "script: an invocation with no mode flag exits 0 silently (no per-edit path remains)"
else
  fail "script: no-flag invocation gave rc=$rc out=$out"
fi
if grep -q -- '--reset-digests' "$HOOK"; then
  fail "script: typos-format.sh still carries a --reset-digests branch"
else
  ok "script: no --reset-digests branch remains"
fi
out="$(printf '{"stop_hook_active":false}' | CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=false bash "$HOOK" --end-of-turn 2>&1)"
rc=$?
if [[ $rc -eq 0 && -z "$out" ]]; then
  ok "script: the kill switch exits 0 before any mode runs"
else
  fail "script: kill switch false gave rc=$rc out=$out"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
