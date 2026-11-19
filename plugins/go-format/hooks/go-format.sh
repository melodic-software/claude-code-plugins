#!/usr/bin/env bash
#   go-format.sh                 the PostToolBatch row
#   go-format.sh --end-of-turn   the opt-in Stop row (go_format_end_of_turn)
#
# PostToolBatch has no matcher, so the row fires on every batch. The launcher
# skips the script unless the payload mentions ".go", and the script then reads
# tool_calls[].tool_input.file_path itself, so a batch with no Go edit costs one
# node process. A file that Read named is never rewritten.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :

# The opt-in Stop row: the pre-commit entry run over the uncommitted changes,
# without rewriting. A file goimports cannot parse exits 2 so the model fixes it
# before the turn ends; once a Stop hook has continued the turn (stop_hook_active)
# the row stays quiet, so it blocks at most once per turn.
if [[ "${1:-}" == --end-of-turn ]]; then
  [[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
  # shellcheck source=hook-utils.sh
  source "$HOOK_DIR/hook-utils.sh"
  hook::git_untrusted_env || exit 0
  err="$("${BASH:-bash}" "$HOOK_DIR/../git-hooks/format.sh" --worktree 2>&1 >/dev/null)" && exit 0
  report=""
  while IFS= read -r line; do
    case "$line" in
    "FAIL: "*" missing. Install: "* | "To skip only while "*" is missing: "*) ;;
    *) report+="$line"$'\n' ;;
    esac
  done <<<"$err"
  [[ -n "${report//[[:space:]]/}" ]] || exit 0
  printf '%s' "$report" >&2
  exit 2
fi

[[ "$INPUT" == *.go* ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
PATHS=$(jq -r '.tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit") | .tool_input.file_path? | strings | select(test("\\.go$"))' <<<"$INPUT" 2>/dev/null) || exit 0
[[ -n "$PATHS" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=../lib/git-hooks/resolve-tool.sh
source "$HOOK_DIR/../lib/git-hooks/resolve-tool.sh"
# shellcheck source=../git-hooks/adapters.sh
source "$HOOK_DIR/../git-hooks/adapters.sh"

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
  hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_GO_FORMAT_LINT_GITIGNORED:-false}" "$file" && continue
  ROOTS+=("$root")
  FILES+=("$file")
done <<<"$PATHS"

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
