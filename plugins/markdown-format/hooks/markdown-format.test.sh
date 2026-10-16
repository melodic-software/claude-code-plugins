#!/usr/bin/env bash
# Black-box contract test for the markdown-format PostToolBatch row, launched exactly
# as hooks.json registers it (node exec-bash.mjs with the row's args).
#
# Proves WIRING: one PostToolBatch row and no PostToolUse row; the row rewrites
# the .md and .mdc files a Write, Edit or MultiEdit in the batch named, once per
# batch, and never anything a Read named; it prints nothing (no finding, no
# disclosure reaches the model) and exits 0; a markdownlint config must govern the
# file (present -> run, absent -> leave bytes untouched) and must not be able to
# run repository code; the config's ignores, .githooks/, gitignored files and the
# kill switch are honored; a batch with no Markdown edit costs only the launcher.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures. The
# row is run from an UNRELATED cwd so any reliance on the caller's working
# directory would surface.
#
# Requires a real markdownlint-cli2: on PATH, else the repository's locked install.
# Without one the behavioral assertions cannot run, so the suite skips.
# test-scope: plugins/markdown-format/.claude-plugin/plugin.json plugins/markdown-format/hooks/hooks.json plugins/markdown-format/prerequisites.json plugins/markdown-format/git-hooks/markdown-gates.sh

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PLUGIN_DATA

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# --- The node_modules walk is bound to prerequisites.json -----------------------
# The shim path is not composed from the manifest, so this case is the binding:
# the manifest lists markdownlint-cli2, jq and node, and the gates state
# markdownlint-cli2's local_bin verbatim.
MANIFEST="$PLUGIN_ROOT/prerequisites.json"
if command -v jq >/dev/null 2>&1 && [[ -f "$MANIFEST" ]]; then
  if jq -e '(.requires | map(.id)) == ["markdownlint-cli2", "jq", "node"] and .requires[0].detect.local_bin == ["node_modules/.bin/markdownlint-cli2"]' "$MANIFEST" >/dev/null 2>&1; then
    ok "manifest: declares exactly markdownlint-cli2 (at node_modules/.bin/markdownlint-cli2), jq and node"
  else
    fail "manifest: expected tools markdownlint-cli2, jq and node with local_bin node_modules/.bin/markdownlint-cli2: $(cat "$MANIFEST")"
  fi
  MF_LOCAL="$(jq -r '.requires[0].detect.local_bin[0]' "$MANIFEST")"
  if [[ -n "$MF_LOCAL" ]] && grep -qF -- "${MF_LOCAL#node_modules/}" "$PLUGIN_ROOT/git-hooks/markdown-gates.sh"; then
    ok "manifest binding: the gates state the manifest's local_bin (${MF_LOCAL#node_modules/})"
  else
    fail "manifest binding: the gates do not state the manifest's local_bin (needle='$MF_LOCAL')"
  fi
else
  fail "manifest binding needs jq and $MANIFEST"
fi

# --- hooks.json: one PostToolBatch row, an opt-in Stop row, no PostToolUse ----
# The batch row takes no matcher and no `if`: the hooks reference says neither
# applies to the event, so its launcher flag is the only filter. The script reads
# the paths itself.
if command -v jq >/dev/null 2>&1 && [[ -f "$HOOKS_JSON" ]]; then
  # shellcheck disable=SC2016 # the CLAUDE_PLUGIN_ROOT placeholders are literal manifest text
  EXPECTED_ROW='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","MARKDOWN_FORMAT_ENABLED","--skip-unless-stdin-contains",".md","${CLAUDE_PLUGIN_ROOT}/hooks/markdown-format.sh"]'
  expect "hooks.json: no PostToolUse row" "0" "$(jq '[.hooks.PostToolUse // [] | .[]] | length' "$HOOKS_JSON")"
  expect "hooks.json: one PostToolBatch group with one handler" "1 1" "$(jq -r '.hooks.PostToolBatch | "\(length) \(.[0].hooks | length)"' "$HOOKS_JSON")"
  expect "hooks.json: the batch handler has no matcher, no if, and runs the script behind the .md prefilter" \
    "node true true $EXPECTED_ROW" \
    "$(jq -r '.hooks.PostToolBatch[0] as $g | $g.hooks[0] | "\(.command) \($g | has("matcher") | not) \(has("if") | not) \(.args | tojson)"' "$HOOKS_JSON")"
  # shellcheck disable=SC2016
  EXPECTED_STOP='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","MARKDOWN_FORMAT_ENABLED","--require-true","MARKDOWN_FORMAT_END_OF_TURN","${CLAUDE_PLUGIN_ROOT}/hooks/markdown-format.sh","--end-of-turn"]'
  expect "hooks.json: the Stop row is gated on the end-of-turn option" "$EXPECTED_STOP" "$(jq -c '.hooks.Stop[0].hooks[0].args' "$HOOKS_JSON")"
  expect "hooks.json: the end-of-turn option is declared, default false" "boolean false" \
    "$(jq -r '.userConfig.markdown_format_end_of_turn | "\(.type) \(.default)"' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  expect "hooks.json: SessionStart holds only the two prerequisite probes" "2" \
    "$(jq '[.hooks.SessionStart[].hooks[]] | length' "$HOOKS_JSON")"
else
  fail "hooks.json assertions need jq and $HOOKS_JSON"
fi

# --- SessionStart probe honors markdown_format_enabled -------------------------
# Runs the hooks.json SessionStart row as the harness spawns it: `node` with the
# row's args, ${CLAUDE_PLUGIN_ROOT} expanded, from an empty cwd, on a PATH that
# holds the system tools and no markdownlint-cli2. The gate is
# `--run-if-unset-or-true` in exec-bash.mjs, so a row without it prints the
# notice for a disabled plugin. A missing node fails the suite instead of
# skipping the cases: every hook row launches through it.
NODE_BIN="$(command -v node 2>/dev/null)"
if [[ -z "$NODE_BIN" ]]; then
  fail "probe-gate: node is not on PATH, and every hook row launches through node hooks/exec-bash.mjs"
else
  PG_WORK="$(mktemp -d)"
  mkdir -p "$PG_WORK/sysbin" "$PG_WORK/cwd"
  for dir in /usr/local/bin /usr/bin /bin; do
    for exe in "$dir"/*; do
      base="${exe##*/}"
      [[ -x "$exe" && "$base" != markdownlint-cli2 && ! -e "$PG_WORK/sysbin/$base" ]] || continue
      MSYS=winsymlinks:nativestrict ln -s "$exe" "$PG_WORK/sysbin/$base"
    done
  done
  PG_ARGS=()
  while IFS= read -r pg_arg; do
    # shellcheck disable=SC2016  # the placeholder is matched literally, as Claude Code substitutes it
    PG_ARGS+=("${pg_arg//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_ROOT}")
  done < <(jq -r '.hooks.SessionStart[0].hooks[0].args[]' "$HOOKS_JSON")
  IFS=$'\t' read -r PG_NAME PG_CHECK PG_INSTALL < <(jq -r '.requires[0] | [.id, .check, (.install | to_entries[0].value)] | @tsv' "$PLUGIN_ROOT/prerequisites.json")

  # run_probe <value|__unset__> -> run the row with markdown_format_enabled set to <value> (or unset).
  run_probe() {
    local v="$1"
    local -a opt=(env -u CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED)
    [[ "$v" == "__unset__" ]] || opt=(env "CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=$v")
    (cd "$PG_WORK/cwd" && printf '{"session_id":"s1"}' |
      "${opt[@]}" PATH="$PG_WORK/sysbin" CLAUDE_PLUGIN_DATA="$(mktemp -d "$PG_WORK/data.XXXXXX")" \
        "$NODE_BIN" "${PG_ARGS[@]}" 2>&1)
  }

  OUT_PG=$(run_probe false)
  RC_PG=$?
  if [[ $RC_PG -eq 0 && -z "$OUT_PG" ]]; then
    ok "probe-gate: markdown_format_enabled=false -> exit 0 and no notice"
  else
    fail "probe-gate: markdown_format_enabled=false should print nothing and exit 0 (rc=$RC_PG out=$OUT_PG)"
  fi
  for v in __unset__ true; do
    label="markdown_format_enabled=$v"
    [[ "$v" == "__unset__" ]] && label="markdown_format_enabled unset"
    OUT_PG=$(run_probe "$v")
    RC_PG=$?
    if [[ $RC_PG -eq 0 && "$OUT_PG" == *"$PG_NAME"* && "$OUT_PG" == *"$PG_CHECK"* && "$OUT_PG" == *"$PG_INSTALL"* ]]; then
      ok "probe-gate: $label -> notice names $PG_NAME, $PG_CHECK and the install line"
    else
      fail "probe-gate: $label should print the missing-markdownlint-cli2 notice (rc=$RC_PG out=$OUT_PG)"
    fi
  done
  rm -rf "${PG_WORK:?}"
fi

# Resolve a real markdownlint-cli2. Skip the rest of the suite when none is available.
REAL_MD="$(command -v markdownlint-cli2 || true)"
[[ -n "$REAL_MD" ]] || REAL_MD="$REPO_ROOT/node_modules/.bin/markdownlint-cli2"
if [[ ! -x "$REAL_MD" ]]; then
  echo "SKIP: no markdownlint-cli2 (put it on PATH or run npm ci) -- remaining markdown-format hook tests skipped"
  echo "PASS=$PASS FAIL=$FAIL"
  exit "$((FAIL > 0 ? 1 : 0))"
fi
PATH="${REAL_MD%/*}:$PATH"
export PATH

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
trap 'rm -rf "$WORK" "$UNRELATED"' EXIT

# The row's args from hooks.json, with the plugin root substituted.
mapfile -t ROW_ARGS < <(jq -r '.hooks.PostToolBatch[0].hooks[0].args[]' "$HOOKS_JSON" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$PLUGIN_ROOT#g")

# new_md_repo <dir> [config_body] -> init a git repo with a .markdownlint-cli2.jsonc
# (unless config_body is the literal NO_CONFIG).
new_md_repo() {
  local r="$1" cfg="${2:-}"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
  if [[ "$cfg" != "NO_CONFIG" ]]; then
    if [[ -n "$cfg" ]]; then
      printf '%s\n' "$cfg" >"$r/.markdownlint-cli2.jsonc"
    else
      printf '{ "config": { "default": true, "MD013": false } }\n' >"$r/.markdownlint-cli2.jsonc"
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
    env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true "$@" node "${ROW_ARGS[@]}" <<<"$p" 2>&1
  )
}

# run_edit <file>: Edit one file in a batch; prints the row's whole output.
run_edit() { fire "$(payload Edit "$1")"; }

# Two documented rule outcomes drive the fixtures: markdownlint MD047 (a file ends
# with one newline) is fixable, and MD033 (no inline HTML) is not.
NO_NL=$'# T\n\ntext'
FIXED=$'# T\n\ntext\n'

# --- Opt-in gate OFF (no markdownlint config) -> file left untouched ----------
REPO_NO="$WORK/no-config"
new_md_repo "$REPO_NO" NO_CONFIG
printf '%s' "$NO_NL" >"$REPO_NO/a.md"
OUT=$(run_edit "$REPO_NO/a.md")
RC=$?
expect "no config: exit 0 and silent" "0|" "$RC|$OUT"
expect "no config: file left untouched" "$NO_NL" "$(cat "$REPO_NO/a.md")"

# A package.json property is no opt-in: markdownlint-cli2 reads it only under --config.
REPO_PJ="$WORK/package-json"
new_md_repo "$REPO_PJ" NO_CONFIG
printf '{"markdownlint-cli2":{"config":{"default":true}}}\n' >"$REPO_PJ/package.json"
printf '%s' "$NO_NL" >"$REPO_PJ/a.md"
run_edit "$REPO_PJ/a.md" >/dev/null
expect "a package.json property does not opt in: file left untouched" "$NO_NL" "$(cat "$REPO_PJ/a.md")"

# --- Rewrites, and prints nothing --------------------------------------------
REPO="$WORK/consumer"
new_md_repo "$REPO"
mkdir -p "$REPO/docs"
printf '%s' "$NO_NL" >"$REPO/docs/fmt.md"
OUT=$(run_edit "$REPO/docs/fmt.md")
RC=$?
expect "Edit of a subdirectory file: fixed" "${FIXED}x" "$(cat "$REPO/docs/fmt.md"; printf x)"
expect "a rewrite prints nothing to the model or the user, exit 0" "0|" "$RC|$OUT"

printf '# T\n\ntext\n' >"$REPO/clean.md"
OUT=$(run_edit "$REPO/clean.md")
expect "a clean file: silent exit 0 and unchanged" "0||$(printf '# T\n\ntext')" "$?|$OUT|$(cat "$REPO/clean.md")"

# Findings no longer reach the model: an unfixable MD033 is neither fixed nor reported.
printf '# T\n\n<b>x</b>\n' >"$REPO/html.md"
OUT=$(run_edit "$REPO/html.md")
expect "a lint finding is not reported (no additionalContext, no systemMessage)" "0|" "$?|$OUT"
expect "the finding's file is not rewritten" "$(printf '# T\n\n<b>x</b>')" "$(cat "$REPO/html.md")"

# A .mdc file is Markdown too.
printf '%s' "$NO_NL" >"$REPO/rule.mdc"
run_edit "$REPO/rule.mdc" >/dev/null
expect "an Edit of a .mdc file is fixed" "${FIXED}x" "$(cat "$REPO/rule.mdc"; printf x)"

# --- The batch -----------------------------------------------------------------
# One call, several files, all rewritten; a Read, a non-Markdown file and a
# duplicate are not.
printf '%s' "$NO_NL" >"$REPO/b1.md"
printf '%s' "$NO_NL" >"$REPO/b2.mdc"
printf '%s' "$NO_NL" >"$REPO/b3.md"
printf 'q' >"$REPO/notes.txt"
BATCH="$(jq -n --arg d "$REPO" '{session_id: "s", hook_event_name: "PostToolBatch", tool_calls: [
  {tool_name: "Write", tool_input: {file_path: "\($d)/b1.md"}, tool_use_id: "1", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/b2.mdc"}, tool_use_id: "2", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/b1.md"}, tool_use_id: "3", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/notes.txt"}, tool_use_id: "4", tool_response: "ok"},
  {tool_name: "Read", tool_input: {file_path: "\($d)/b3.md"}, tool_use_id: "5", tool_response: "1\t# T"},
  {tool_name: "Bash", tool_input: {command: "ls b3.md"}, tool_use_id: "6", tool_response: "b3.md"}]}')"
OUT=$(fire "$BATCH")
expect "a mixed batch prints nothing" "0|" "$?|$OUT"
expect "batch: a Write'd .md is rewritten" "${FIXED}x" "$(cat "$REPO/b1.md"; printf x)"
expect "batch: an Edit'd .mdc is rewritten" "${FIXED}x" "$(cat "$REPO/b2.mdc"; printf x)"
expect "batch: a Read'd .md is never rewritten" "$NO_NL" "$(cat "$REPO/b3.md")"
expect "batch: a non-Markdown file is untouched" "q" "$(cat "$REPO/notes.txt")"

# A file with a finding does not stop its neighbors from being rewritten.
printf '# T\n\n<b>x</b>\n' >"$REPO/bad.md"
printf '%s' "$NO_NL" >"$REPO/good.md"
fire "$(payload Edit "$REPO/bad.md" "$REPO/good.md")" >/dev/null
expect "a file with a finding does not stop another file in the batch" "${FIXED}x" "$(cat "$REPO/good.md"; printf x)"

printf '%s' "$NO_NL" >"$REPO/multi.md"
fire "$(payload MultiEdit "$REPO/multi.md")" >/dev/null
expect "a MultiEdit'd file is rewritten" "${FIXED}x" "$(cat "$REPO/multi.md"; printf x)"

# --- Skips ----------------------------------------------------------------------
# .githooks/ holds installed copies of check scripts, never rewritten here.
mkdir -p "$REPO/.githooks/markdown-format"
printf '%s' "$NO_NL" >"$REPO/.githooks/markdown-format/copy.md"
fire "$(payload Write "$REPO/.githooks/markdown-format/copy.md")" >/dev/null
expect "a file under .githooks/ is skipped" "$NO_NL" "$(cat "$REPO/.githooks/markdown-format/copy.md")"

# The config's ignores hold for an explicitly passed path, silently.
REPO_EX="$WORK/ignores-config"
new_md_repo "$REPO_EX" '{ "ignores": ["gen/**"] }'
mkdir -p "$REPO_EX/gen"
printf '%s' "$NO_NL" >"$REPO_EX/gen/g.md"
OUT=$(run_edit "$REPO_EX/gen/g.md")
expect "an ignored file is left untouched and silent" "0|$NO_NL" "$?|$OUT$(cat "$REPO_EX/gen/g.md")"

# A nested config opts in only its subtree.
REPO_NE="$WORK/nested"
new_md_repo "$REPO_NE" NO_CONFIG
mkdir -p "$REPO_NE/docs/deep"
printf '{ "default": true }\n' >"$REPO_NE/docs/.markdownlint.json"
printf '%s' "$NO_NL" >"$REPO_NE/docs/deep/n.md"
printf '%s' "$NO_NL" >"$REPO_NE/top.md"
fire "$(payload Edit "$REPO_NE/docs/deep/n.md" "$REPO_NE/top.md")" >/dev/null
expect "a nested config governs a file below it" "${FIXED}x" "$(cat "$REPO_NE/docs/deep/n.md"; printf x)"
expect "a file outside the nested config is untouched" "$NO_NL" "$(cat "$REPO_NE/top.md")"

# A config that can run repository code is never run, and nothing says so.
for cfg_case in "cjs" "customRules" "backslash"; do
  REPO_CODE="$WORK/code-$cfg_case"
  new_md_repo "$REPO_CODE" NO_CONFIG
  case "$cfg_case" in
  cjs) printf 'module.exports = { config: { default: true } };\n' >"$REPO_CODE/.markdownlint-cli2.cjs" ;;
  customRules) printf '{ "config": { "default": true }, "customRules": ["./rule.cjs"] }\n' >"$REPO_CODE/.markdownlint-cli2.jsonc" ;;
  backslash) printf '{ "config": { "default": true }, "ignores": ["a\\\\.md"] }\n' >"$REPO_CODE/.markdownlint-cli2.jsonc" ;;
  *) ;;
  esac
  printf '%s' "$NO_NL" >"$REPO_CODE/a.md"
  OUT=$(run_edit "$REPO_CODE/a.md")
  expect "code-capable config ($cfg_case): silent and the file untouched" "0|$NO_NL" "$?|$OUT$(cat "$REPO_CODE/a.md")"
done

# The kill switch.
printf '%s' "$NO_NL" >"$REPO/kill.md"
OUT=$(fire "$(payload Edit "$REPO/kill.md")" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=false)
expect "kill switch off: silent and the file untouched" "0|$NO_NL" "$?|$OUT$(cat "$REPO/kill.md")"

# A repo-local node_modules/.bin shim resolves when PATH has none.
FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink node sh; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
REPO_LB="$WORK/local-bin"
new_md_repo "$REPO_LB"
mkdir -p "$REPO_LB/node_modules/.bin" "$REPO_LB/docs"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_MD" >"$REPO_LB/node_modules/.bin/markdownlint-cli2"
chmod +x "$REPO_LB/node_modules/.bin/markdownlint-cli2"
printf '%s' "$NO_NL" >"$REPO_LB/docs/l.md"
fire "$(payload Edit "$REPO_LB/docs/l.md")" PATH="$FAKEBIN" >/dev/null
expect "repo-local shim: resolved and the file fixed" "${FIXED}x" "$(cat "$REPO_LB/docs/l.md"; printf x)"

# markdownlint-cli2 absent: the file is skipped silently; the SessionStart probe reports the gap.
REPO_NR="$WORK/no-md"
new_md_repo "$REPO_NR"
printf '%s' "$NO_NL" >"$REPO_NR/a.md"
OUT=$(fire "$(payload Edit "$REPO_NR/a.md")" PATH="$FAKEBIN")
expect "markdownlint-cli2 absent: silent exit 0 and the file untouched" "0|$NO_NL" "$?|$OUT$(cat "$REPO_NR/a.md")"

# A shim whose symlink leaves the repository is not run.
REPO_ES="$WORK/escaping-shim"
new_md_repo "$REPO_ES"
mkdir -p "$REPO_ES/node_modules/.bin" "$WORK/outside"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_MD" >"$WORK/outside/markdownlint-cli2"
chmod +x "$WORK/outside/markdownlint-cli2"
ln -s "$WORK/outside/markdownlint-cli2" "$REPO_ES/node_modules/.bin/markdownlint-cli2"
printf '%s' "$NO_NL" >"$REPO_ES/a.md"
fire "$(payload Edit "$REPO_ES/a.md")" PATH="$FAKEBIN" >/dev/null
expect "an escaping node_modules/.bin symlink is not run" "$NO_NL" "$(cat "$REPO_ES/a.md")"

# Gitignored path: neither rewritten by default, unless markdown_format_lint_gitignored is set.
REPO_IGN="$WORK/gitignored"
new_md_repo "$REPO_IGN"
git -C "$REPO_IGN" config core.excludesFile /dev/null
printf '.work/\n' >"$REPO_IGN/.gitignore"
mkdir -p "$REPO_IGN/.work"
printf '%s' "$NO_NL" >"$REPO_IGN/.work/scratch.md"
run_edit "$REPO_IGN/.work/scratch.md" >/dev/null
expect "gitignored: file not rewritten" "$NO_NL" "$(cat "$REPO_IGN/.work/scratch.md")"
fire "$(payload Edit "$REPO_IGN/.work/scratch.md")" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_LINT_GITIGNORED=true >/dev/null
expect "gitignored + markdown_format_lint_gitignored=true: file fixed" "${FIXED}x" "$(cat "$REPO_IGN/.work/scratch.md"; printf x)"

# A markdown file outside every git working tree is left alone, config or not.
OUTSIDE="$WORK/outside-tree"
mkdir -p "$OUTSIDE"
printf '{ "config": { "default": true } }\n' >"$OUTSIDE/.markdownlint-cli2.jsonc"
printf '%s' "$NO_NL" >"$OUTSIDE/scratch.md"
run_edit "$OUTSIDE/scratch.md" >/dev/null
expect "outside a git working tree: file untouched" "$NO_NL" "$(cat "$OUTSIDE/scratch.md")"

# Symlinked repo root: the file reached through a symlinked directory is still rewritten.
if ln -s "$WORK/symlink-real" "$WORK/symlink-link" 2>/dev/null; then
  REPO_SL="$WORK/symlink-real"
  new_md_repo "$REPO_SL"
  mkdir -p "$REPO_SL/pkg"
  printf '%s' "$NO_NL" >"$REPO_SL/pkg/mod.md"
  run_edit "$WORK/symlink-link/pkg/mod.md" >/dev/null
  expect "symlinked root: the file is rewritten" "${FIXED}x" "$(cat "$REPO_SL/pkg/mod.md"; printf x)"
else
  echo "SKIP: symlinks unavailable on this filesystem -- symlinked-root case skipped"
fi

# A file symlinked out of the repository is not followed.
REPO_FS="$WORK/file-symlink"
new_md_repo "$REPO_FS"
printf '%s' "$NO_NL" >"$WORK/external.md"
if ln -s "$WORK/external.md" "$REPO_FS/link.md" 2>/dev/null; then
  run_edit "$REPO_FS/link.md" >/dev/null
  expect "a symlinked .md pointing outside the repository is not rewritten" "$NO_NL" "$(cat "$WORK/external.md")"
fi

# --- Spawn budget ----------------------------------------------------------------
# PostToolBatch has no matcher, so the row fires on every batch of every session.
# A batch that never mentions .md costs only the node launcher.
CENSUS="$REPO_ROOT/scripts/hook-census.sh"
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1; then
  out="$(bash "$CENSUS" markdown-format PostToolBatch markdown-format.sh \
    '{"session_id":"census","hook_event_name":"PostToolBatch","cwd":"@DIR@","tool_calls":[{"tool_name":"Read","tool_input":{"file_path":"@DIR@/main.py"},"tool_use_id":"toolu_census","tool_response":"import os"}]}' \
    --check 'test ! -s "$HOOK_STDOUT"')"
  expect "spawn budget: a batch with no Markdown costs only the node launcher" "spawns=1" "${out%% *}"
else
  echo "NOTE: strace or scripts/hook-census.sh absent; the spawn budget case did not run."
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
