#!/usr/bin/env bash
# Black-box contract test for the biome-format PostToolBatch row, launched exactly
# as hooks.json registers it (node exec-bash.mjs with the row's args).
#
# Proves WIRING: one PostToolBatch row and no PostToolUse row; the row rewrites
# the .ts, .tsx, .js, .jsx, .mjs, .cjs, .mts, .cts, .json and .jsonc files a
# Write, Edit or MultiEdit in the batch named, once per Biome config directory per
# batch, and never anything a Read named; it prints nothing (no finding, no
# disclosure reaches the model) and exits 0; a Biome config must govern the file
# (present -> run, absent -> leave bytes untouched; the topmost config in the
# repository wins; the hidden .biome.json does not opt in); the config's own
# ignores, .githooks/, gitignored files and the kill switch are honored; a batch
# with no matching edit costs only the launcher and one bash.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures.
# Each repo gets a node_modules/.bin/biome shim that forwards to a real Biome, so
# the hook's node_modules resolution path is exercised. The row is run from an
# UNRELATED cwd so any reliance on the caller's working directory would surface
# (Biome discovers config from the directory the hook cds to, not the caller's).
#
# Requires a real Biome binary: $BIOME_TEST_BIN if set, else `biome` on PATH.
# Without one the behavioral assertions cannot run, so the suite skips.
# test-scope: plugins/biome-format/.claude-plugin/plugin.json plugins/biome-format/hooks/hooks.json plugins/biome-format/prerequisites.json

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG BIOME_CONFIG_PATH

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/biome-format.sh"
PLUGIN_ROOT="${HOOK_DIR%/*}"
HOOKS_JSON="$HOOK_DIR/hooks.json"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"

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
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1: want [$2] got [$3]"; fi
}

# --- The local-bin walk is bound to prerequisites.json --------------------------
# The walk is not composed from the manifest, so this case is the binding: the
# manifest lists biome, jq and node, and the walk states biome's local_bin
# verbatim.
MANIFEST="$PLUGIN_ROOT/prerequisites.json"
if command -v jq >/dev/null 2>&1 && [[ -f "$MANIFEST" ]]; then
  if jq -e '(.requires | map(.id)) == ["biome", "jq", "node"] and .requires[0].detect.local_bin == ["node_modules/.bin/biome"]' "$MANIFEST" >/dev/null 2>&1; then
    ok "manifest: declares exactly biome (at node_modules/.bin/biome), jq and node"
  else
    fail "manifest: expected tools biome, jq and node with local_bin node_modules/.bin/biome: $(cat "$MANIFEST")"
  fi
  MF_LOCAL="$(jq -r '.requires[0].detect.local_bin[0]' "$MANIFEST")"
  WALK_FN="$(sed -n '/^biome_local_bin_here()/,/^}/p' "$HOOK")"
  if [[ -n "$MF_LOCAL" ]] && grep -qF -- "$MF_LOCAL" <<<"$WALK_FN"; then
    ok "manifest binding: hook states the manifest's local_bin ($MF_LOCAL)"
  else
    fail "manifest binding: hook does not state the manifest's local_bin (needle='$MF_LOCAL')"
  fi
else
  fail "manifest binding needs jq and $MANIFEST"
fi

# --- hooks.json: one PostToolBatch row, an opt-in Stop row, no PostToolUse ----
# The batch row takes no matcher and no `if`: the hooks reference says neither
# applies to the event. The launcher flag takes one text, which cannot cover ten
# extensions, so the script filters; the row carries only the kill-switch gate.
if command -v jq >/dev/null 2>&1 && [[ -f "$HOOKS_JSON" ]]; then
  # shellcheck disable=SC2016 # the CLAUDE_PLUGIN_ROOT placeholders are literal manifest text
  EXPECTED_ROW='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","BIOME_FORMAT_ENABLED","${CLAUDE_PLUGIN_ROOT}/hooks/biome-format.sh"]'
  expect "hooks.json: no PostToolUse row" "0" "$(jq '[.hooks.PostToolUse // [] | .[]] | length' "$HOOKS_JSON")"
  expect "hooks.json: one PostToolBatch group with one handler" "1 1" "$(jq -r '.hooks.PostToolBatch | "\(length) \(.[0].hooks | length)"' "$HOOKS_JSON")"
  expect "hooks.json: the batch handler has no matcher, no if, and runs the script behind the kill switch" \
    "node true true $EXPECTED_ROW" \
    "$(jq -r '.hooks.PostToolBatch[0] as $g | $g.hooks[0] | "\(.command) \($g | has("matcher") | not) \(has("if") | not) \(.args | tojson)"' "$HOOKS_JSON")"
  # shellcheck disable=SC2016
  EXPECTED_STOP='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","BIOME_FORMAT_ENABLED","--require-true","BIOME_FORMAT_END_OF_TURN","${CLAUDE_PLUGIN_ROOT}/hooks/biome-format.sh","--end-of-turn"]'
  expect "hooks.json: the Stop row is gated on the end-of-turn option" "$EXPECTED_STOP" "$(jq -c '.hooks.Stop[0].hooks[0].args' "$HOOKS_JSON")"
  expect "hooks.json: the end-of-turn option is declared, default false" "boolean false" \
    "$(jq -r '.userConfig.biome_format_end_of_turn | "\(.type) \(.default)"' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
else
  fail "hooks.json assertions need jq and $HOOKS_JSON"
fi

# --- SessionStart probe honors biome_format_enabled ---------------------------
# Runs the hooks.json SessionStart row as the harness spawns it: `node` with the
# row's args, ${CLAUDE_PLUGIN_ROOT} expanded, from an empty cwd, on a PATH that
# holds the system tools and no biome. The gate is `--run-if-unset-or-true` in
# exec-bash.mjs, so a row without it prints the notice for a disabled plugin.
# Needs no real Biome. A missing node fails the suite instead of skipping the
# cases: every hook row launches through it.
NODE_BIN="$(command -v node 2>/dev/null)"
if [[ -z "$NODE_BIN" ]]; then
  fail "probe-gate: node is not on PATH, and every hook row launches through node hooks/exec-bash.mjs"
else
  PG_WORK="$(mktemp -d)"
  mkdir -p "$PG_WORK/sysbin" "$PG_WORK/cwd"
  for dir in /usr/local/bin /usr/bin /bin; do
    for exe in "$dir"/*; do
      base="${exe##*/}"
      [[ -x "$exe" && "$base" != biome && ! -e "$PG_WORK/sysbin/$base" ]] || continue
      MSYS=winsymlinks:nativestrict ln -s "$exe" "$PG_WORK/sysbin/$base"
    done
  done
  PG_ARGS=()
  while IFS= read -r pg_arg; do
    # shellcheck disable=SC2016  # the placeholder is matched literally, as Claude Code substitutes it
    PG_ARGS+=("${pg_arg//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_ROOT}")
  done < <(jq -r '.hooks.SessionStart[0].hooks[0].args[]' "$HOOKS_JSON")
  IFS=$'\t' read -r PG_NAME PG_CHECK PG_INSTALL < <(jq -r '.requires[0] | [.id, .check, (.install | to_entries[0].value)] | @tsv' "$PLUGIN_ROOT/prerequisites.json")

  # run_probe <value|__unset__> -> run the row with biome_format_enabled set to <value> (or unset).
  run_probe() {
    local v="$1"
    local -a opt=(env -u CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED)
    [[ "$v" == "__unset__" ]] || opt=(env "CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED=$v")
    (cd "$PG_WORK/cwd" && printf '{"session_id":"s1"}' |
      "${opt[@]}" PATH="$PG_WORK/sysbin" CLAUDE_PLUGIN_DATA="$(mktemp -d "$PG_WORK/data.XXXXXX")" \
        "$NODE_BIN" "${PG_ARGS[@]}" 2>&1)
  }

  OUT_PG=$(run_probe false)
  RC_PG=$?
  if [[ $RC_PG -eq 0 && -z "$OUT_PG" ]]; then
    ok "probe-gate: biome_format_enabled=false -> exit 0 and no notice"
  else
    fail "probe-gate: biome_format_enabled=false should print nothing and exit 0 (rc=$RC_PG out=$OUT_PG)"
  fi
  for v in __unset__ true; do
    label="biome_format_enabled=$v"
    [[ "$v" == "__unset__" ]] && label="biome_format_enabled unset"
    OUT_PG=$(run_probe "$v")
    RC_PG=$?
    if [[ $RC_PG -eq 0 && "$OUT_PG" == *"$PG_NAME"* && "$OUT_PG" == *"$PG_CHECK"* && "$OUT_PG" == *"$PG_INSTALL"* ]]; then
      ok "probe-gate: $label -> notice names $PG_NAME, $PG_CHECK and the install line"
    else
      fail "probe-gate: $label should print the missing-biome notice (rc=$RC_PG out=$OUT_PG)"
    fi
  done
  rm -rf "${PG_WORK:?}"
fi

# Resolve a real Biome binary. node_modules/.bin/biome shims in each fixture
# forward to this. Skip the rest of the suite when none is available.
if [[ -n "${BIOME_TEST_BIN:-}" && -x "${BIOME_TEST_BIN}" ]]; then
  REAL_BIOME="${BIOME_TEST_BIN}"
elif command -v biome >/dev/null 2>&1; then
  REAL_BIOME="$(command -v biome)"
else
  echo "SKIP: no Biome binary (set BIOME_TEST_BIN or put biome on PATH) -- remaining biome-format hook tests skipped"
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
  exit
fi

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
trap 'rm -rf "$WORK" "$UNRELATED"' EXIT

# The row's args from hooks.json, with the plugin root substituted.
mapfile -t ROW_ARGS < <(jq -r '.hooks.PostToolBatch[0].hooks[0].args[]' "$HOOKS_JSON" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$PLUGIN_ROOT#g")

# new_biome_repo <dir> [config_body] -> init a git repo with a node_modules biome
# shim and (unless config_body is the literal NO_CONFIG) a biome.json.
new_biome_repo() {
  local r="$1" cfg="${2:-}"
  mkdir -p "$r/node_modules/.bin"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
  {
    printf '#!/usr/bin/env bash\n'
    printf 'exec "%s" "$@"\n' "$REAL_BIOME"
  } >"$r/node_modules/.bin/biome"
  chmod +x "$r/node_modules/.bin/biome"
  if [[ "$cfg" != "NO_CONFIG" ]]; then
    if [[ -n "$cfg" ]]; then
      printf '%s\n' "$cfg" >"$r/biome.json"
    else
      printf '{}\n' >"$r/biome.json"
    fi
  fi
}

# payload <tool> <file>...: a PostToolBatch payload with one call per file.
payload() {
  local tool="$1"
  shift
  jq -n --arg t "$tool" '{session_id: "s", hook_event_name: "PostToolBatch", tool_calls: [$ARGS.positional[] | {tool_name: $t, tool_input: {file_path: .}, tool_use_id: "toolu_x", tool_response: "ok"}]}' --args "$@"
}

# fire <payload> [env...]: the registered row, from an unrelated cwd. CLAUDE_PROJECT_DIR
# stays unset so scoping falls to git-working-tree membership.
fire() {
  local p="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED=true "$@" node "${ROW_ARGS[@]}" <<<"$p" 2>&1
  )
}

# run_edit <file>: Edit one file in a batch; prints the row's whole output.
run_edit() { fire "$(payload Edit "$1")"; }

# --- Opt-in gate OFF (no biome.json) -> file left untouched -------------------
# A repo with Biome installed but NO config must not have its files rewritten to
# Biome's built-in defaults.
REPO_NO="$WORK/no-config"
new_biome_repo "$REPO_NO" NO_CONFIG
printf 'const x=1;var y=2\n' >"$REPO_NO/nofmt.ts"
OUT=$(run_edit "$REPO_NO/nofmt.ts")
expect "no config: exit 0 and silent" "0|" "$?|$OUT"
expect "no config: file left untouched" "const x=1;var y=2" "$(cat "$REPO_NO/nofmt.ts")"

# .biome.json/.biome.jsonc are only loaded by Biome >= 2.4, so they must not
# opt in: an older Biome would reformat with built-in defaults.
REPO_DOT="$WORK/dotted-only"
new_biome_repo "$REPO_DOT" NO_CONFIG
printf '{}\n' >"$REPO_DOT/.biome.json"
printf 'const x=1;var y=2\n' >"$REPO_DOT/dot.ts"
run_edit "$REPO_DOT/dot.ts" >/dev/null
expect "hidden .biome.json only: file left untouched" "const x=1;var y=2" "$(cat "$REPO_DOT/dot.ts")"

# --- Rewrites, and prints nothing -----------------------------------------------
REPO="$WORK/consumer"
new_biome_repo "$REPO"
mkdir -p "$REPO/src" "$REPO/lib"
printf 'export const a=1;export const b=2\n' >"$REPO/src/fmt.ts"
OUT=$(run_edit "$REPO/src/fmt.ts")
expect "Edit of a subdirectory file: formatted" "$(printf 'export const a = 1;\nexport const b = 2;')" "$(cat "$REPO/src/fmt.ts")"
expect "a rewrite prints nothing to the model or the user, exit 0" "0|" "$?|$OUT"

printf 'export const x = 1;\n' >"$REPO/clean.ts"
OUT=$(run_edit "$REPO/clean.ts")
expect "a clean file: silent exit 0 and unchanged" "0||export const x = 1;" "$?|$OUT|$(cat "$REPO/clean.ts")"

# Findings no longer reach the model: an unused variable is neither fixed nor reported.
printf 'const unusedVar=1\n' >"$REPO/lib/lint.ts"
OUT=$(run_edit "$REPO/lib/lint.ts")
expect "a lint finding is not reported (no additionalContext, no systemMessage)" "0|" "$?|$OUT"
expect "the finding's file is still formatted" "const unusedVar = 1;" "$(cat "$REPO/lib/lint.ts")"

printf 'const = ;\n' >"$REPO/syntax.ts"
OUT=$(run_edit "$REPO/syntax.ts")
expect "a mid-edit syntax error is silent" "0|" "$?|$OUT"

printf '{"b":2,"a":1}\n' >"$REPO/data.json"
run_edit "$REPO/data.json" >/dev/null
expect "a JSON file is formatted" '{ "b": 2, "a": 1 }' "$(cat "$REPO/data.json")"

# A safe fix applies: the imports sort. An unsafe one (dropping an unused import)
# stays for the person or the pre-commit report.
printf 'import { b } from "./b";\nimport { a } from "./a";\nexport { a, b };\n' >"$REPO/imports.ts"
run_edit "$REPO/imports.ts" >/dev/null
expect "a safe fix is applied: the imports sort" "$(printf 'import { a } from "./a";\nimport { b } from "./b";')" "$(head -2 "$REPO/imports.ts")"
printf 'import { a } from "./a";\n' >"$REPO/unused.ts"
run_edit "$REPO/unused.ts" >/dev/null
expect "an unused import survives the in-session rewrite" 'import { a } from "./a";' "$(cat "$REPO/unused.ts")"

# BIOME_CONFIG_PATH is a config-path override; the repo config stays authoritative.
REPO_ENV="$WORK/env-override"
new_biome_repo "$REPO_ENV" '{ "javascript": { "formatter": { "quoteStyle": "single" } } }'
EXT_CFG="$WORK/external-cfg"
mkdir -p "$EXT_CFG"
printf '%s\n' '{ "javascript": { "formatter": { "quoteStyle": "double" } } }' >"$EXT_CFG/biome.json"
printf 'const s = "hi";\nexport { s };\n' >"$REPO_ENV/q.ts"
fire "$(payload Edit "$REPO_ENV/q.ts")" BIOME_CONFIG_PATH="$EXT_CFG" >/dev/null
expect "BIOME_CONFIG_PATH is neutralized: the repo config is authoritative" "const s = 'hi';" "$(head -1 "$REPO_ENV/q.ts")"

# The topmost config governs, and runs a nested one beneath it.
REPO_NEST="$WORK/nested"
new_biome_repo "$REPO_NEST" '{ "formatter": { "indentStyle": "space", "indentWidth": 2 } }'
mkdir -p "$REPO_NEST/pkg/sub"
printf '{ "root": false, "extends": "//", "formatter": { "indentWidth": 8 } }\n' >"$REPO_NEST/pkg/biome.json"
printf 'export function f() { return 1 }\n' >"$REPO_NEST/pkg/sub/f.ts"
printf 'export function g() { return 1 }\n' >"$REPO_NEST/g.ts"
fire "$(payload Edit "$REPO_NEST/pkg/sub/f.ts" "$REPO_NEST/g.ts")" >/dev/null
expect "the nested file formats under the root config extended by its own" "$(printf 'export function f() {\n        return 1;\n}')" "$(cat "$REPO_NEST/pkg/sub/f.ts")"
expect "a file outside the nested config formats under the root config" "$(printf 'export function g() {\n  return 1;\n}')" "$(cat "$REPO_NEST/g.ts")"

# --- The batch -------------------------------------------------------------------
# One call, several files, all rewritten; a Read, a non-Biome file and a
# duplicate are not.
printf 'export const a=1\n' >"$REPO/b1.ts"
printf 'export const b=1\n' >"$REPO/b2.mjs"
printf 'export const c=1\n' >"$REPO/b3.ts"
printf 'q=1\n' >"$REPO/notes.txt"
BATCH="$(jq -n --arg d "$REPO" '{session_id: "s", hook_event_name: "PostToolBatch", tool_calls: [
  {tool_name: "Write", tool_input: {file_path: "\($d)/b1.ts"}, tool_use_id: "1", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/b2.mjs"}, tool_use_id: "2", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/b1.ts"}, tool_use_id: "3", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/notes.txt"}, tool_use_id: "4", tool_response: "ok"},
  {tool_name: "Read", tool_input: {file_path: "\($d)/b3.ts"}, tool_use_id: "5", tool_response: "1\texport const c=1"},
  {tool_name: "Bash", tool_input: {command: "ls b3.ts"}, tool_use_id: "6", tool_response: "b3.ts"}]}')"
OUT=$(fire "$BATCH")
expect "a mixed batch prints nothing" "0|" "$?|$OUT"
expect "batch: a Write'd .ts is rewritten" "export const a = 1;" "$(cat "$REPO/b1.ts")"
expect "batch: an Edit'd .mjs is rewritten" "export const b = 1;" "$(cat "$REPO/b2.mjs")"
expect "batch: a Read'd .ts is never rewritten" "export const c=1" "$(cat "$REPO/b3.ts")"
expect "batch: a non-Biome file is untouched" "q=1" "$(cat "$REPO/notes.txt")"

# A file that does not parse does not stop its neighbors from being rewritten.
printf 'const = ;\n' >"$REPO/bad.ts"
printf 'export const z=1\n' >"$REPO/good.ts"
fire "$(payload Edit "$REPO/bad.ts" "$REPO/good.ts")" >/dev/null
expect "a syntax-error file does not stop another file in the batch" "export const z = 1;" "$(cat "$REPO/good.ts")"

printf 'export const m=1\n' >"$REPO/multi.cts"
fire "$(payload MultiEdit "$REPO/multi.cts")" >/dev/null
expect "a MultiEdit'd file is rewritten" "export const m = 1;" "$(cat "$REPO/multi.cts")"

# Every extension in the set is rewritten.
for ext in tsx js jsx cjs mts jsonc; do
  case "$ext" in
  jsonc) printf '{"e":1}\n' >"$REPO/ext.$ext" ;;
  cjs) printf 'const e=1\n' >"$REPO/ext.$ext" ;;
  *) printf 'export const e=1\n' >"$REPO/ext.$ext" ;;
  esac
  run_edit "$REPO/ext.$ext" >/dev/null
  case "$ext" in
  jsonc) want='{ "e": 1 }' ;;
  cjs) want='const e = 1;' ;;
  *) want='export const e = 1;' ;;
  esac
  expect "extension .$ext is rewritten" "$want" "$(cat "$REPO/ext.$ext")"
done

# --- Skips ------------------------------------------------------------------------
# .githooks/ holds installed copies of check scripts, never rewritten here.
mkdir -p "$REPO/.githooks/biome-format"
printf 'export const g=1\n' >"$REPO/.githooks/biome-format/copy.ts"
fire "$(payload Write "$REPO/.githooks/biome-format/copy.ts")" >/dev/null
expect "a file under .githooks/ is skipped" "export const g=1" "$(cat "$REPO/.githooks/biome-format/copy.ts")"

# The config's ignores hold for an explicitly passed path, silently.
REPO_IGN="$WORK/ignore-config"
new_biome_repo "$REPO_IGN" '{ "files": { "includes": ["**", "!**/generated/**"] } }'
mkdir -p "$REPO_IGN/generated"
printf 'export const z=1\n' >"$REPO_IGN/generated/gen.ts"
OUT=$(run_edit "$REPO_IGN/generated/gen.ts")
expect "an ignored file is left untouched and silent" "0|export const z=1" "$?|$OUT$(cat "$REPO_IGN/generated/gen.ts")"

# The kill switch.
printf 'export const k=1\n' >"$REPO/kill.ts"
OUT=$(fire "$(payload Edit "$REPO/kill.ts")" CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED=false)
expect "kill switch off: silent and the file untouched" "0|export const k=1" "$?|$OUT$(cat "$REPO/kill.ts")"

# No node_modules shim -> PATH resolves Biome.
REPO_PATH="$WORK/path-fallback"
mkdir -p "$REPO_PATH"
git -C "$REPO_PATH" init -q
printf '{}\n' >"$REPO_PATH/biome.json"
printf 'export const p=1\n' >"$REPO_PATH/p.ts"
fire "$(payload Edit "$REPO_PATH/p.ts")" PATH="$(dirname "$REAL_BIOME"):$PATH" >/dev/null
expect "PATH fallback: Biome resolved and file formatted" "export const p = 1;" "$(cat "$REPO_PATH/p.ts")"

# Biome absent: the file is skipped silently; the SessionStart probe reports the gap.
REPO_NB="$WORK/no-biome"
mkdir -p "$REPO_NB"
git -C "$REPO_NB" init -q
printf '{}\n' >"$REPO_NB/biome.json"
printf 'export const a=1\n' >"$REPO_NB/app.ts"
FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink node; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
OUT=$(fire "$(payload Edit "$REPO_NB/app.ts")" PATH="$FAKEBIN")
expect "biome absent: silent exit 0 and the file untouched" "0|export const a=1" "$?|$OUT$(cat "$REPO_NB/app.ts")"

# Gitignored path: neither rewritten by default, unless biome_format_lint_gitignored is set.
REPO_GI="$WORK/gitignored"
new_biome_repo "$REPO_GI"
git -C "$REPO_GI" config core.excludesFile /dev/null
printf '.work/\nnode_modules/\n' >"$REPO_GI/.gitignore"
mkdir -p "$REPO_GI/.work"
printf 'export const x=1\n' >"$REPO_GI/.work/scratch.ts"
run_edit "$REPO_GI/.work/scratch.ts" >/dev/null
expect "gitignored: file not rewritten" "export const x=1" "$(cat "$REPO_GI/.work/scratch.ts")"
fire "$(payload Edit "$REPO_GI/.work/scratch.ts")" CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_LINT_GITIGNORED=true >/dev/null
expect "gitignored + biome_format_lint_gitignored=true: file formatted" "export const x = 1;" "$(cat "$REPO_GI/.work/scratch.ts")"

# Symlinked repo root: the file reached through a symlinked directory is still rewritten.
if ln -s "$WORK/symlink-real" "$WORK/symlink-link" 2>/dev/null; then
  REPO_SL="$WORK/symlink-real"
  new_biome_repo "$REPO_SL"
  mkdir -p "$REPO_SL/pkg"
  printf 'export const x=1\n' >"$REPO_SL/pkg/mod.ts"
  run_edit "$WORK/symlink-link/pkg/mod.ts" >/dev/null
  expect "symlinked root: the file is rewritten" "export const x = 1;" "$(cat "$REPO_SL/pkg/mod.ts")"
else
  echo "SKIP: symlinks unavailable on this filesystem -- symlinked-root case skipped"
fi

# --- Spawn budget ----------------------------------------------------------------
# PostToolBatch has no matcher, so the row fires on every batch of every session.
# A batch that names no Biome file costs the node launcher and one bash, which
# decides in a pattern match before any other process starts.
CENSUS="$REPO_ROOT/scripts/hook-census.sh"
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1; then
  out="$(bash "$CENSUS" biome-format PostToolBatch biome-format.sh \
    '{"session_id":"census","hook_event_name":"PostToolBatch","cwd":"@DIR@","tool_calls":[{"tool_name":"Read","tool_input":{"file_path":"@DIR@/README.md"},"tool_use_id":"toolu_census","tool_response":"# readme"}]}' \
    --check 'test ! -s "$HOOK_STDOUT"')"
  expect "spawn budget: a batch with no Biome file costs the launcher and one bash (3 spawns)" "spawns=3" "${out%% *}"
else
  echo "NOTE: strace or scripts/hook-census.sh absent; the spawn budget case did not run."
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
