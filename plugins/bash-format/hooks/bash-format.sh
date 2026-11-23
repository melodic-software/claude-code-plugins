#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :

if [[ "${1:-}" == --end-of-turn ]]; then
  [[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
  # shellcheck source=hook-utils.sh
  source "$HOOK_DIR/hook-utils.sh"
  hook::git_untrusted_env || exit 0
  err="$("${BASH:-bash}" "$HOOK_DIR/../git-hooks/lint.sh" --worktree 2>&1 >/dev/null)" && exit 0
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

[[ "$INPUT" == *'sh"'* ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v shfmt >/dev/null 2>&1 || exit 0
PATHS=$(jq -r '.tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit") | .tool_input.file_path? | strings | select(test("\\.(sh|bash)$"))' <<<"$INPUT" 2>/dev/null) || exit 0
[[ -n "$PATHS" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=../git-hooks/shfmt-rewrite.sh
source "$HOOK_DIR/../git-hooks/shfmt-rewrite.sh"
# shellcheck source=../lib/git-hooks/resolve-tool.sh
source "$HOOK_DIR/../lib/git-hooks/resolve-tool.sh"
# shellcheck source=../git-hooks/adapters.sh
source "$HOOK_DIR/../git-hooks/adapters.sh"

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
  hook::read_file_path_to file "{\"tool_input\":{\"file_path\":\"$escaped\"}}" || continue
  [[ "$file" == */.githooks/* ]] && continue
  hook::dirname_to dir "$file"
  hook::repo_root_to root "$dir" || :
  [[ -d "$root" ]] || continue
  rt_resolve "$file" format "$root"
  [[ "$RT_SOURCE" == adapter:shfmt ]] || continue
  hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_BASH_FORMAT_LINT_GITIGNORED:-false}" "$file" && continue
  FILES+=("$file")
done <<<"$PATHS"

for file in ${FILES[@]+"${FILES[@]}"}; do
  tool_path_to target "$file"
  [[ -f "$target" ]] || continue
  shfmt_rewrite "$target" >/dev/null 2>&1 || :
done
exit 0
