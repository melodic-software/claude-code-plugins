#!/usr/bin/env bash
# Registration and prerequisite tests for the actionlint plugin's Claude Code
# hooks. actionlint only reports, so no hook runs per edit or per batch: the
# manifest registers no PostToolUse or PostToolBatch row, no digest-reset
# SessionStart row, one opt-in Stop row and the two SessionStart probes. The
# Stop row's behavior is tested in actionlint-end-of-turn.test.sh and the
# pre-commit entry's in git-hooks/actionlint-check.test.sh.
# test-scope: plugins/actionlint/hooks/hooks.json plugins/actionlint/.claude-plugin/plugin.json plugins/actionlint/lib/prerequisites.mjs plugins/actionlint/prerequisites.json
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${HOOK_DIR%/*}"
HOOKS_JSON="$HOOK_DIR/hooks.json"
MANIFEST="$PLUGIN_ROOT/prerequisites.json"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"

for tool in jq node; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "SKIP: $tool not on PATH -- actionlint hook tests skipped"
    exit 0
  }
done

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

expect "hooks.json registers events Stop and SessionStart only: no per-edit and no per-batch row" \
  "SessionStart,Stop" "$(jq -r '.hooks | keys | join(",")' "$HOOKS_JSON")"
expect "no SessionStart row resets a findings digest" "0" \
  "$(jq '[.hooks.SessionStart[].hooks[] | select((.args // []) | index("--reset-digests"))] | length' "$HOOKS_JSON")"
expect "the Stop row is gated on the end-of-turn option" "ACTIONLINT_END_OF_TURN" \
  "$(jq -r '.hooks.Stop[0].hooks[0].args | .[index("--require-true") + 1]' "$HOOKS_JSON")"
expect "the end-of-turn option defaults to false" "false" "$(jq -r '.userConfig.actionlint_end_of_turn.default' "$PLUGIN_JSON")"
expect "the plugin declares only the options a hook reads" "actionlint_enabled,actionlint_end_of_turn" \
  "$(jq -r '.userConfig | keys | join(",")' "$PLUGIN_JSON")"
expect "the git-hook entry is a report-only pre-commit entry" "pre-commit false" \
  "$(jq -r '.entries[0] | "\(.event) \(.rewrites)"' "$PLUGIN_ROOT/git-hooks/entries.json")"

# --- The manifest lists the plugin's tools ------------------------------------
expect "manifest: declares exactly actionlint and node" "actionlint,node" "$(jq -r '.requires | map(.id) | join(",")' "$MANIFEST")"
IFS=$'\t' read -r MF_NAME MF_CHECK MF_INSTALL < <(jq -r '.requires[0] | [.id, .check, (.install | to_entries[0].value)] | @tsv' "$MANIFEST")

# --- SessionStart probe honors actionlint_enabled ------------------------------
# Runs the hooks.json SessionStart row as the harness spawns it: `node` with the
# row's args, ${CLAUDE_PLUGIN_ROOT} expanded, from an empty cwd, on a PATH that
# holds the system tools and no actionlint. The gate is `--run-if-unset-or-true`
# in exec-bash.mjs, so a row without it prints the notice for a disabled plugin.
NODE_BIN="$(command -v node)"
PG_WORK="$(mktemp -d)"
trap 'rm -rf "$PG_WORK"' EXIT
mkdir -p "$PG_WORK/sysbin" "$PG_WORK/cwd"
for dir in /usr/local/bin /usr/bin /bin; do
  for exe in "$dir"/*; do
    base="${exe##*/}"
    [[ -x "$exe" && "$base" != actionlint && ! -e "$PG_WORK/sysbin/$base" ]] || continue
    MSYS=winsymlinks:nativestrict ln -s "$exe" "$PG_WORK/sysbin/$base"
  done
done
PG_ARGS=()
while IFS= read -r pg_arg; do
  # shellcheck disable=SC2016 # the placeholder is matched literally, as Claude Code substitutes it
  PG_ARGS+=("${pg_arg//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_ROOT}")
done < <(jq -r '.hooks.SessionStart[0].hooks[0].args[]' "$HOOKS_JSON")

# run_probe <value|__unset__> -> run the row with actionlint_enabled set to <value> (or unset)
run_probe() {
  local v="$1" data
  data="$(mktemp -d "$PG_WORK/data.XXXXXX")"
  local -a opt=(env -u CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED)
  [[ "$v" == "__unset__" ]] || opt=(env "CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=$v")
  (cd "$PG_WORK/cwd" && printf '{"session_id":"s1"}' |
    "${opt[@]}" PATH="$PG_WORK/sysbin" CLAUDE_PLUGIN_DATA="$data" \
      "$NODE_BIN" "${PG_ARGS[@]}" 2>&1)
}

OUT_PG=$(run_probe false)
RC_PG=$?
expect "probe-gate: actionlint_enabled=false -> exit 0 and no notice" "0|" "$RC_PG|$OUT_PG"
for v in __unset__ true; do
  label="actionlint_enabled=$v"
  [[ "$v" == "__unset__" ]] && label="actionlint_enabled unset"
  OUT_PG=$(run_probe "$v")
  RC_PG=$?
  if [[ $RC_PG -eq 0 && "$OUT_PG" == *"$MF_NAME"* && "$OUT_PG" == *"$MF_CHECK"* && "$OUT_PG" == *"$MF_INSTALL"* ]]; then
    echo "ok: probe-gate: $label -> notice names $MF_NAME, $MF_CHECK and the install line"
    PASS=$((PASS + 1))
  else
    echo "FAIL: probe-gate: $label should print the missing-actionlint notice (rc=$RC_PG out=$OUT_PG)" >&2
    FAIL=$((FAIL + 1))
  fi
done

echo "actionlint hooks: $PASS passed, $FAIL failed"
((FAIL == 0))
