#!/usr/bin/env bash
# PostToolBatch hook: rewrite the Python files a batch of tool calls wrote.
#
#   ruff-format.sh                 the PostToolBatch row
#   ruff-format.sh --end-of-turn   the opt-in Stop row (ruff_format_end_of_turn)
#
# Rewrites only: `ruff check --fix` (safe fixes) and `ruff format`, once per
# batch over every .py and .pyi file a Write, Edit or MultiEdit in the batch
# named. It prints nothing and always exits 0, so no finding ever reaches the
# model per edit; findings are the pre-commit entry's job
# (git-hooks/ruff-check.sh), which also rewrites for every author.
#
# PostToolBatch has no matcher, so the row fires on every batch. The launcher
# skips the script unless the payload mentions ".py", and the script then reads
# tool_calls[].tool_input.file_path itself, so a batch with no Python edit costs
# one node process. A file that Read named is never rewritten.
#
# Opt-in: a file is rewritten only when a Ruff configuration governs it (a
# .ruff.toml, ruff.toml, or pyproject.toml with a [tool.ruff] section, found by
# walking up from the file to the repo root, as Ruff itself discovers it). A repo
# that has not adopted a Ruff config is left untouched. Ruff comes from the
# repo's own .venv (walking up from the file) or PATH, never downloaded. Known
# limitation: the bare `[tool]` header with `ruff = { ... }` inline table is not
# recognized, so such a repo is skipped (a missed opt-in, never a wrong edit).
#
# --unfixable F401 protects an import that lands one edit before the code that
# uses it; the pre-commit entry removes unused imports once the change is whole.
# Files under .githooks/ are installed copies and are skipped, as are gitignored
# files unless ruff_format_lint_gitignored is true. The batch payload carries no
# pre-edit bytes, so a file that already drifted from the config is rewritten
# whole, as the pre-commit entry would.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :

# The opt-in Stop row: the pre-commit entry run over the uncommitted changes,
# without rewriting. Findings exit 2 so the model fixes them before the turn
# ends; once a Stop hook has continued the turn (stop_hook_active) the row stays
# quiet, so it blocks at most once per turn.
if [[ "${1:-}" == --end-of-turn ]]; then
  [[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
  "${BASH:-bash}" "$HOOK_DIR/../git-hooks/ruff-check.sh" --worktree >/dev/null && exit 0
  exit 2
fi

[[ "$INPUT" == *.py* ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
PATHS=$(jq -r '.tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit") | .tool_input.file_path? | strings | select(test("\\.pyi?$"))' <<<"$INPUT" 2>/dev/null) || exit 0
[[ -n "$PATHS" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

# shellcheck disable=SC2329  # invoked by name, as hook::walk_up_to's predicate
ruff_config_here() {
  local dir="$1" name
  for name in .ruff.toml ruff.toml; do
    [[ -f "$dir/$name" ]] && return 0
  done
  [[ -f "$dir/pyproject.toml" ]] &&
    grep -qE '^[[:space:]]*\[tool\.ruff(\]|[.])' "$dir/pyproject.toml" 2>/dev/null
}

RUFF_BIN=""
# shellcheck disable=SC2329  # invoked by name, as hook::walk_up_to's predicate
ruff_venv_bin_here() {
  local cand
  for cand in "$1/.venv/bin/ruff" "$1/.venv/Scripts/ruff.exe"; do
    if [[ -x "$cand" ]]; then
      RUFF_BIN="$cand"
      return 0
    fi
  done
  return 1
}

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
  hook::walk_up_to config_dir "$dir" "$root" ruff_config_here || continue
  hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_LINT_GITIGNORED:-false}" "$file" && continue
  ROOTS+=("$root")
  FILES+=("$file")
done <<<"$PATHS"

# One check and one format run per repository root, over all its files.
done_roots=$'\n'
for i in "${!ROOTS[@]}"; do
  root="${ROOTS[i]}"
  [[ "$done_roots" != *$'\n'"$root"$'\n'* ]] || continue
  done_roots+="$root"$'\n'
  group=()
  for j in "${!ROOTS[@]}"; do
    [[ "${ROOTS[j]}" == "$root" ]] && group+=("${FILES[j]}")
  done
  RUFF_BIN=""
  hook::dirname_to dir "${group[0]}"
  hook::walk_up_to venv_dir "$dir" "$root" ruff_venv_bin_here || :
  if [[ -z "$RUFF_BIN" ]]; then
    command -v ruff >/dev/null 2>&1 && RUFF_BIN=ruff
  fi
  [[ -n "$RUFF_BIN" ]] || continue
  # --force-exclude honors the config's excludes for explicit paths; --no-cache
  # keeps a .ruff_cache out of the consumer's repo.
  (cd "$root" && "$RUFF_BIN" check --fix --no-unsafe-fixes --unfixable F401 --force-exclude --no-cache --quiet -- "${group[@]}") >/dev/null 2>&1 || :
  (cd "$root" && "$RUFF_BIN" format --force-exclude --no-cache --quiet -- "${group[@]}") >/dev/null 2>&1 || :
done
exit 0
