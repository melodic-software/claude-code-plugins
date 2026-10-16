#!/usr/bin/env bash
# PostToolBatch hook: rewrite the JavaScript, TypeScript and JSON files a batch of
# tool calls wrote.
#
#   biome-format.sh                 the PostToolBatch row
#   biome-format.sh --end-of-turn   the opt-in Stop row (biome_format_end_of_turn)
#
# Rewrites only: `biome check --write` (safe fixes, formatting, import sorting),
# once per Biome config directory over every .ts, .tsx, .js, .jsx, .mjs, .cjs,
# .mts, .cts, .json and .jsonc file a Write, Edit or MultiEdit in the batch named.
# It prints nothing and always exits 0, so no finding ever reaches the model per
# edit; findings are the pre-commit entry's job (git-hooks/biome-check.sh), which
# also rewrites for every author.
#
# PostToolBatch has no matcher, so the row fires on every batch. The launcher
# cannot prefilter on ten extensions (its flag takes one text), so this script
# does it with a bash pattern before any other process starts, then reads
# tool_calls[].tool_input.file_path itself. A file that Read named is never
# rewritten.
#
# Opt-in: a file is rewritten only when a biome.json or biome.jsonc governs it,
# found by walking up from the file to the repo root; the topmost one wins, and
# Biome runs from that directory, as Biome itself discovers configuration. A repo
# that has not adopted a Biome config is left untouched. Biome comes from the
# repo's node_modules/.bin (walking up from the file) or PATH, never downloaded.
# Only the canonical names count, not the hidden .biome.json variants, which
# Biome loads from 2.4 on. Files under .githooks/ are installed copies and are
# skipped, as are gitignored files unless biome_format_lint_gitignored is true.
# The batch payload carries no pre-edit bytes, so a file that already drifted from
# the config is rewritten whole, as the pre-commit entry would.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :

# The opt-in Stop row: the pre-commit entry run over the uncommitted changes,
# without rewriting. Findings exit 2 so the model fixes them before the turn
# ends; once a Stop hook has continued the turn (stop_hook_active) the row stays
# quiet, so it blocks at most once per turn.
if [[ "${1:-}" == --end-of-turn ]]; then
  [[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
  "${BASH:-bash}" "$HOOK_DIR/../git-hooks/biome-check.sh" --worktree >/dev/null && exit 0
  exit 2
fi

[[ "$INPUT" =~ \.(ts|tsx|js|jsx|mjs|cjs|mts|cts|json|jsonc)\" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0  # silent-skip-ok: the SessionStart prerequisites probe reports a missing jq; the batch row never speaks to the model
PATHS=$(jq -r '.tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit") | .tool_input.file_path? | strings | select(test("\\.(ts|tsx|js|jsx|mjs|cjs|mts|cts|json|jsonc)$"))' <<<"$INPUT" 2>/dev/null) || exit 0
[[ -n "$PATHS" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

# shellcheck disable=SC2329  # invoked by name, as hook::walk_up_to's predicate
biome_config_here() {
  local name
  for name in biome.json biome.jsonc; do
    [[ -f "$1/$name" ]] && return 0
  done
  return 1
}

BIOME_BIN=""
# shellcheck disable=SC2329  # invoked by name, as hook::walk_up_to's predicate
biome_local_bin_here() {
  [[ -f "$1/node_modules/.bin/biome" ]] || return 1
  BIOME_BIN="$1/node_modules/.bin/biome"
  return 0
}

CONFIGS=()
FILES=()
ROOTS=()
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
  config_dir=""
  hook::walk_up_to config_dir "$dir" "$root" biome_config_here topmost || continue
  hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_LINT_GITIGNORED:-false}" "$file" && continue
  CONFIGS+=("$config_dir")
  FILES+=("$file")
  ROOTS+=("$root")
done <<<"$PATHS"

# One run per Biome config directory, from that directory with the files named
# relative to it, as Biome discovers configuration from the working directory.
done_dirs=$'\n'
for i in "${!CONFIGS[@]}"; do
  config_dir="${CONFIGS[i]}"
  [[ "$done_dirs" != *$'\n'"$config_dir"$'\n'* ]] || continue
  done_dirs+="$config_dir"$'\n'
  root="${ROOTS[i]}"
  group=()
  for j in "${!CONFIGS[@]}"; do
    [[ "${CONFIGS[j]}" == "$config_dir" ]] || continue
    rel="${FILES[j]#"$config_dir"/}"
    group+=("$rel")
  done
  BIOME_BIN=""
  hook::dirname_to dir "${FILES[i]}"
  hook::walk_up_to bin_dir "$dir" "$root" biome_local_bin_here || :
  if [[ -z "$BIOME_BIN" ]]; then
    command -v biome >/dev/null 2>&1 && BIOME_BIN=biome
  fi
  [[ -n "$BIOME_BIN" ]] || continue
  # BIOME_CONFIG_PATH is unset: Biome reads it as a config-path override, which
  # would make the rewrite follow another config than the one that opted in.
  (cd "$config_dir" && env -u BIOME_CONFIG_PATH "$BIOME_BIN" check --write --no-errors-on-unmatched -- "${group[@]}") >/dev/null 2>&1 || :
done
exit 0
