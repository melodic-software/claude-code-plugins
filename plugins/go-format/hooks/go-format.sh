#!/usr/bin/env bash
# PostToolBatch hook: rewrite the Go files a batch of tool calls wrote.
#
#   go-format.sh                 the PostToolBatch row
#   go-format.sh --end-of-turn   the opt-in Stop row (go_format_end_of_turn)
#
# Rewrites only: `goimports -w`, once per batch over every .go file a Write, Edit
# or MultiEdit in the batch named. It prints nothing and always exits 0, so no
# finding or disclosure ever reaches the model per edit; a file goimports cannot
# parse is left as it is and the pre-commit entry (git-hooks/goimports-format.sh)
# reports it for every author.
#
# PostToolBatch has no matcher, so the row fires on every batch. The launcher
# skips the script unless the payload mentions ".go", and the script then reads
# tool_calls[].tool_input.file_path itself, so a batch with no Go edit costs one
# node process. A file that Read named is never rewritten.
#
# No consumer-config opt-in gate: goimports documents itself as a replacement for
# an editor's gofmt-on-save. A file whose leading comment block carries Go's
# `// Code generated ... DO NOT EDIT.` marker is skipped, as are files under
# .githooks/ (installed copies) and gitignored files unless
# go_format_lint_gitignored is true. goimports comes from PATH, never downloaded.
# The -local grouping prefix is the file's own module path (`go list -m`), so a
# repo's internal imports keep their own group; without go or a module the plain
# default grouping applies.

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
  "${BASH:-bash}" "$HOOK_DIR/../git-hooks/goimports-format.sh" --worktree >/dev/null && exit 0
  exit 2
fi

[[ "$INPUT" == *.go* ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v goimports >/dev/null 2>&1 || exit 0
PATHS=$(jq -r '.tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit") | .tool_input.file_path? | strings | select(test("\\.go$"))' <<<"$INPUT" 2>/dev/null) || exit 0
[[ -n "$PATHS" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

# generated <path>: 0 when the file's leading comment and blank-line run holds
# the generated-code marker. The scan is a stand-in for go/ast.IsGenerated: it
# tracks /* */ blocks, tolerates a BOM and CRLF, and stops at the first line
# that is neither blank nor a comment.
generated() {
  local line trimmed in_block=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#$'\xEF\xBB\xBF'}"
    if ((in_block)); then
      [[ "$line" == *'*/'* ]] && in_block=0
      continue
    fi
    [[ -n "${line//[[:space:]]/}" ]] || continue
    trimmed="${line#"${line%%[![:space:]]*}"}"
    if [[ "$trimmed" == //* ]]; then
      [[ "$line" =~ ^//\ Code\ generated\ .*\ DO\ NOT\ EDIT\.$ ]] && return 0
      continue
    fi
    if [[ "$trimmed" == /\** ]]; then
      [[ "$trimmed" == *'*/'* ]] || in_block=1
      continue
    fi
    break
  done <"$1"
  return 1
}

ROOTS=()
FILES=()
PREFIXES=()
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
  generated "$file" && continue
  prefix=""
  if command -v go >/dev/null 2>&1; then
    prefix="$(cd "$dir" 2>/dev/null && go list -m 2>/dev/null)" || prefix=""
    [[ "$prefix" == "command-line-arguments" ]] && prefix=""
  fi
  ROOTS+=("$root")
  FILES+=("$file")
  PREFIXES+=("$prefix")
done <<<"$PATHS"

# One goimports run per repository root and -local prefix, over all its files.
done_keys=$'\n'
for i in "${!FILES[@]}"; do
  key="${ROOTS[i]}"$'\t'"${PREFIXES[i]}"
  [[ "$done_keys" != *$'\n'"$key"$'\n'* ]] || continue
  done_keys+="$key"$'\n'
  group=()
  for j in "${!FILES[@]}"; do
    [[ "${ROOTS[j]}"$'\t'"${PREFIXES[j]}" == "$key" ]] && group+=("${FILES[j]}")
  done
  args=(-w)
  [[ -n "${PREFIXES[i]}" ]] && args+=(-local "${PREFIXES[i]}")
  (cd "${ROOTS[i]}" && goimports "${args[@]}" -- "${group[@]}") >/dev/null 2>&1 || :
done
exit 0
