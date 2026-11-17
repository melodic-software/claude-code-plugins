#!/usr/bin/env bash
# PostToolBatch hook: format the JavaScript, TypeScript and JSON files a batch of
# tool calls wrote.
#
#   javascript-format.sh                 the PostToolBatch row
#   javascript-format.sh --end-of-turn   the opt-in Stop row (javascript_format_end_of_turn)
#
# Formats only: once per batch, over every .ts, .tsx, .js, .jsx, .mjs, .cjs,
# .mts, .cts, .json and .jsonc file a Write, Edit or MultiEdit in the batch
# named, the Biome adapter runs where a biome.json or biome.jsonc governs the
# file (git-hooks/adapters.sh, through lib/git-hooks/resolve-tool.sh: the
# formatter and the assist actions the repository's config enables, import
# sorting by default, with the linter off). A .claude/ecosystems/ record is
# never run here; /toolchain:lint runs it. No lint fix runs here; findings are
# the lint entry's job (git-hooks/lint.sh). It prints nothing and always exits
# 0, so nothing reaches the model per edit.
#
# PostToolBatch has no matcher, so the row fires on every batch. The launcher
# cannot prefilter on ten extensions (its flag takes one text), so this script
# does it with a bash pattern before any other process starts, then reads
# tool_calls[].tool_input.file_path itself. A file that Read named is never
# rewritten. Files under .githooks/ are installed copies and are skipped, as are
# gitignored files unless javascript_format_lint_gitignored is true. The batch
# payload carries no pre-edit bytes, so a file that already drifted from the
# config is rewritten whole, as the pre-commit entry would.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_JAVASCRIPT_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :

# The opt-in Stop row: the lint entry run over the uncommitted changes, without
# rewriting. Findings exit 2 so the model fixes them before the turn ends; once
# a Stop hook has continued the turn (stop_hook_active) the row stays quiet, so
# it blocks at most once per turn.
if [[ "${1:-}" == --end-of-turn ]]; then
  [[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
  err="$("${BASH:-bash}" "$HOOK_DIR/../git-hooks/lint.sh" --worktree 2>&1 >/dev/null)" && exit 0
  # A missing linter is a host problem: the SessionStart probe reports it, and
  # blocking every turn end on it would not help the model. Only those lines
  # are dropped; any finding printed beside them is still handed back.
  report=""
  while IFS= read -r line; do
    case "$line" in
    "FAIL: "*" missing. Install: "* | "To skip only while "*" is missing: "*) ;;
    *) report+="$line"$'\n' ;;
    esac
  done <<<"$err"
  # silent-skip-ok: only missing-tool lines remained, which the SessionStart probe reports.
  [[ -n "${report//[[:space:]]/}" ]] || exit 0
  printf '%s' "$report" >&2
  exit 2
fi

[[ "$INPUT" =~ \.(ts|tsx|js|jsx|mjs|cjs|mts|cts|json|jsonc)\" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0  # silent-skip-ok: the SessionStart prerequisites probe reports a missing jq; the batch row never speaks to the model
PATHS=$(jq -r '.tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit") | .tool_input.file_path? | strings | select(test("\\.(ts|tsx|js|jsx|mjs|cjs|mts|cts|json|jsonc)$"))' <<<"$INPUT" 2>/dev/null) || exit 0
[[ -n "$PATHS" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=../lib/git-hooks/resolve-tool.sh
source "$HOOK_DIR/../lib/git-hooks/resolve-tool.sh"
# shellcheck source=../git-hooks/adapters.sh
source "$HOOK_DIR/../git-hooks/adapters.sh"

# Per repository root, the files to format, in batch order.
ROOTS=()
FILES=()
seen=$'\n'
while IFS= read -r path; do
  path="${path%$'\r'}"
  [[ -n "$path" && "$seen" != *$'\n'"$path"$'\n'* ]] || continue
  seen+="$path"$'\n'
  escaped=""
  hook::json_escape_to escaped "$path"
  # Existence, symlink and project membership, as for a single-file hook.
  hook::read_file_path_to file "{\"tool_input\":{\"file_path\":\"$escaped\"}}" || continue
  [[ "$file" == */.githooks/* ]] && continue
  hook::dirname_to dir "$file"
  hook::repo_root_to root "$dir" || :
  [[ -d "$root" ]] || continue
  hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_JAVASCRIPT_FORMAT_LINT_GITIGNORED:-false}" "$file" && continue
  ROOTS+=("$root")
  FILES+=("$file")
done <<<"$PATHS"

# One run per repository root and resolved command (one per Biome config
# directory), over all its files.
done_roots=$'\n'
for i in "${!ROOTS[@]}"; do
  root="${ROOTS[i]}"
  [[ "$done_roots" != *$'\n'"$root"$'\n'* ]] || continue
  done_roots+="$root"$'\n'
  group=()
  for j in "${!ROOTS[@]}"; do
    [[ "${ROOTS[j]}" == "$root" ]] && group+=("${FILES[j]}")
  done
  rt_group format "$root" "${group[@]}"
  for ((g = 0; g < RT_GN; g++)); do
    rt_use "$g"
    rt_found "$RT_BIN" || continue
    rt_run "${RT_FILES[@]}" >/dev/null 2>&1 || :
  done
done
exit 0
