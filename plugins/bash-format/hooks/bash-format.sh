#!/usr/bin/env bash
# PostToolBatch hook: format the shell scripts a batch of tool calls wrote.
#
#   bash-format.sh                 the PostToolBatch row
#   bash-format.sh --end-of-turn   the opt-in Stop row (bash_format_end_of_turn)
#
# Rewrites only: shfmt, once per batch over every .sh and .bash file a Write,
# Edit or MultiEdit in the batch named. It prints nothing and always exits 0, so
# no finding ever reaches the model per edit; ShellCheck findings are the
# pre-commit entry's job (git-hooks/shell-check.sh), which also formats for every
# author.
#
# PostToolBatch has no matcher, so the row fires on every batch. The launcher
# skips the script unless the payload holds a string ending in "sh" (which both
# extensions do), and the script then reads tool_calls[].tool_input.file_path
# itself, so a batch with no shell edit costs one node process. A file that Read
# named is never rewritten.
#
# Opt-in: shfmt runs only for a file an .editorconfig section governs (see
# git-hooks/shfmt-rewrite.sh); without that opt-in the file is left as written
# rather than rewritten to shfmt's built-in defaults. A file the repository
# gitignores is skipped unless bash_format_lint_gitignored is true, and so is
# anything under .githooks/ (installed copies). The batch payload carries no
# pre-edit bytes, so a file that already drifted from the repo's style is
# formatted whole, as the pre-commit entry would.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :

# The opt-in Stop row: the pre-commit entry run over the uncommitted changes,
# without rewriting. Findings exit 2 so the model fixes them before the turn
# ends; once a Stop hook has continued the turn (stop_hook_active) the row stays
# quiet, so it blocks at most once per turn.
if [[ "${1:-}" == --end-of-turn ]]; then
  [[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
  "${BASH:-bash}" "$HOOK_DIR/../git-hooks/shell-check.sh" --worktree >/dev/null && exit 0
  exit 2
fi

[[ "$INPUT" == *'sh"'* ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v shfmt >/dev/null 2>&1 || exit 0
PATHS=$(jq -r '.tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit") | .tool_input.file_path? | strings | select(test("\\.(sh|bash)$"))' <<<"$INPUT" 2>/dev/null) || exit 0
[[ -n "$PATHS" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=../git-hooks/shfmt-rewrite.sh
source "$HOOK_DIR/../git-hooks/shfmt-rewrite.sh"

# shfmt and jq read the file, so on Windows/MSYS hand them cygpath's mixed long
# form of a POSIX mount path (`/c/...`); elsewhere the path is used unchanged.
# cygpath is looked up only on the Windows bash hosts: elsewhere the lookup
# misses after probing every PATH directory, which on WSL includes the /mnt/c
# entries, one 9P round trip each.
tool_path_to() {
  local dest="$1" lm
  printf -v "$dest" '%s' "$2"
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32)
    if command -v cygpath >/dev/null 2>&1; then
      lm=$(cygpath -lm -- "$2" 2>/dev/null)
      [[ -n "$lm" && -f "$lm" ]] && printf -v "$dest" '%s' "$lm"
    fi
    ;;
  *) ;;
  esac
}

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
  hook::walk_up_to config_dir "$dir" "$root" editorconfig_shell_section_here || continue
  hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_BASH_FORMAT_LINT_GITIGNORED:-false}" "$file" && continue
  FILES+=("$file")
done <<<"$PATHS"

# shfmt finds the .editorconfig from the file's own path, so no directory change.
for file in ${FILES[@]+"${FILES[@]}"}; do
  tool_path_to target "$file"
  # Re-check just before mutating: the file can vanish between the payload and now.
  [[ -f "$target" ]] || continue
  shfmt_rewrite "$target" >/dev/null 2>&1 || :
done
exit 0
