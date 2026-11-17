#!/usr/bin/env bash
# PostToolBatch hook: format the Go files a batch of tool calls wrote.
#
#   go-format.sh                 the PostToolBatch row
#   go-format.sh --end-of-turn   the opt-in Stop row (go_format_end_of_turn)
#
# Formats only: once per batch, over every .go file a Write, Edit or MultiEdit
# in the batch named, the goimports adapter runs (git-hooks/adapters.sh,
# through lib/git-hooks/resolve-tool.sh): gofmt formatting and import ordering,
# never adding or removing an import. A .claude/ecosystems/ record is never run
# here; /toolchain:lint runs it. It prints nothing and always exits 0, so no
# finding or disclosure ever reaches the model per edit; a file goimports
# cannot parse is left as it is and the pre-commit format entry
# (git-hooks/format.sh) reports it for every author.
#
# PostToolBatch has no matcher, so the row fires on every batch. The launcher
# skips the script unless the payload mentions ".go", and the script then reads
# tool_calls[].tool_input.file_path itself, so a batch with no Go edit costs one
# node process. A file that Read named is never rewritten.
#
# No consumer-config opt-in gate, by design (the adapter's header says why). A
# generated file is skipped, as are files under .githooks/ (installed copies)
# and gitignored files unless go_format_lint_gitignored is true. goimports
# comes from PATH, never downloaded.

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
  err="$("${BASH:-bash}" "$HOOK_DIR/../git-hooks/format.sh" --worktree 2>&1 >/dev/null)" && exit 0
  # A missing goimports is a host problem: the SessionStart probe reports it, and
  # blocking every turn end on it would not help the model. Only those lines
  # are dropped; any error printed beside them is still handed back.
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

[[ "$INPUT" == *.go* ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0  # silent-skip-ok: the SessionStart prerequisites probe reports a missing jq; the batch row never speaks to the model
PATHS=$(jq -r '.tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit") | .tool_input.file_path? | strings | select(test("\\.go$"))' <<<"$INPUT" 2>/dev/null) || exit 0
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
  hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_GO_FORMAT_LINT_GITIGNORED:-false}" "$file" && continue
  ROOTS+=("$root")
  FILES+=("$file")
done <<<"$PATHS"

# One goimports run per repository root and resolved command (its -local
# prefix), over all its files.
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
    rt_found "$RT_BIN" || continue  # silent-skip-ok: the SessionStart prerequisites probe reports a missing goimports; pre-commit fails an agent commit on it
    rt_run "${RT_FILES[@]}" >/dev/null 2>&1 || :
  done
done
exit 0
