#!/usr/bin/env bash
# PostToolBatch hook: format the Python files a batch of tool calls wrote.
#
#   python-format.sh                 the PostToolBatch row
#   python-format.sh --end-of-turn   the opt-in Stop row (python_format_end_of_turn)
#
# Formats only: once per batch, over every .py and .pyi file a Write, Edit or
# MultiEdit in the batch named, the format command each file resolves to
# through lib/git-hooks/resolve-tool.sh runs: the repository's approved python
# record (fix-cmd), else the Ruff adapter (git-hooks/adapters.sh: import
# sorting where the repository's config selects it, then `ruff format`), else
# nothing. No lint autofix runs here; findings are the lint entry's job
# (git-hooks/lint.sh). It prints nothing and always exits 0, so nothing reaches
# the model per edit. An unapproved or unreadable record runs nothing here;
# setup check reports it.
#
# PostToolBatch has no matcher, so the row fires on every batch. The launcher
# skips the script unless the payload mentions ".py", and the script then reads
# tool_calls[].tool_input.file_path itself, so a batch with no Python edit costs
# one node process. A file that Read named is never rewritten. Files under
# .githooks/ are installed copies and are skipped, as are gitignored files
# unless python_format_lint_gitignored is true. The batch payload carries no
# pre-edit bytes, so a file that already drifted from the config is rewritten
# whole, as the pre-commit entry would.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_PYTHON_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :

# The opt-in Stop row: the pre-commit entry run over the uncommitted changes,
# without rewriting. Findings exit 2 so the model fixes them before the turn
# ends; once a Stop hook has continued the turn (stop_hook_active) the row stays
# quiet, so it blocks at most once per turn.
if [[ "${1:-}" == --end-of-turn ]]; then
  [[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
  err="$("${BASH:-bash}" "$HOOK_DIR/../git-hooks/lint.sh" --worktree 2>&1 >/dev/null)" && exit 0
  # silent-skip-ok: a missing linter is reported by the SessionStart probe (an adapter tool) or setup check (a record tool); blocking every turn end on a host problem would not help the model.
  [[ "$err" == "FAIL: "*" missing. Install: "* ]] && exit 0
  printf '%s\n' "$err" >&2
  exit 2
fi

[[ "$INPUT" == *.py* ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0  # silent-skip-ok: the SessionStart prerequisites probe reports a missing jq; the batch row never speaks to the model
PATHS=$(jq -r '.tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit") | .tool_input.file_path? | strings | select(test("\\.pyi?$"))' <<<"$INPUT" 2>/dev/null) || exit 0
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
  hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_PYTHON_FORMAT_LINT_GITIGNORED:-false}" "$file" && continue
  ROOTS+=("$root")
  FILES+=("$file")
done <<<"$PATHS"

# One run per repository root and resolved command, over all its files.
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
