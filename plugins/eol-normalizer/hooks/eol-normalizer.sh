#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :

[[ "$INPUT" == *'"Write"'* || "$INPUT" == *'Edit"'* ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
PATHS=$(jq -r '.tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit") | .tool_input.file_path? | strings' <<<"$INPUT" 2>/dev/null) || exit 0
[[ -n "$PATHS" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=normalize-eol.sh
source "$HOOK_DIR/normalize-eol.sh"

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
  plan=$(normalize_eol_plan "$dir" "$file")
  [[ "${plan##* }" == 1 ]] || continue
  hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_LINT_GITIGNORED:-false}" "$file" && continue
  normalize_eol_apply "${plan%% *}" "$file"
done <<<"$PATHS"
exit 0
