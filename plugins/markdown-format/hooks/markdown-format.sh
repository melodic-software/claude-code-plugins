#!/usr/bin/env bash
# PostToolBatch hook: format the Markdown files a batch of tool calls wrote.
#
#   markdown-format.sh                 the PostToolBatch row
#   markdown-format.sh --end-of-turn   the Stop row (markdown_format_end_of_turn)
#
# Formats only: once per batch, over every .md and .mdc file a Write, Edit or
# MultiEdit in the batch named, the markdownlint-cli2 adapter runs `--fix`
# where a markdownlint config governs the file (git-hooks/adapters.sh, through
# lib/git-hooks/resolve-tool.sh). A .claude/ecosystems/ record is never run
# here; /toolchain:lint runs it. It prints nothing and always exits 0, so no
# finding ever reaches the model per edit; findings are the lint entry's job
# (git-hooks/lint.sh).
#
# PostToolBatch has no matcher, so the row fires on every batch. The launcher
# skips the script unless the payload mentions ".md", and the script then reads
# tool_calls[].tool_input.file_path itself, so a batch with no Markdown edit costs
# one node process. A file that Read named is never rewritten.
#
# Opt-in: a file is rewritten only when a markdownlint config governs it and the
# config either cannot run repository code or runs it in a state the user
# approved (git-hooks/markdown-gates.sh; an unapproved state is skipped silently
# here, and the lint entry reports it at commit). A repository without a config
# has chosen no Markdown style, so it is left untouched. markdownlint-cli2 comes
# from PATH or the repo's own node_modules/.bin, never downloaded. Files under
# .githooks/ are installed copies and are skipped, as are gitignored files
# unless markdown_format_lint_gitignored is true. The batch payload carries no
# pre-edit bytes, so a file that already drifted from the config is rewritten
# whole, as the pre-commit format entry would.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :

# The Stop row: the lint entry run over the uncommitted changes, which rewrites
# nothing. With markdown_format_end_of_turn unset the findings go to the user
# as a systemMessage on exit 0, so the turn ends; set to true they exit 2, so
# the model fixes them before the turn ends. Once a Stop hook has continued the
# turn (stop_hook_active) the row stays quiet, so it blocks at most once per turn.
if [[ "${1:-}" == --end-of-turn ]]; then
  [[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
  err="$("${BASH:-bash}" "$HOOK_DIR/../git-hooks/lint.sh" --worktree 2>&1 >/dev/null)" && exit 0
  # A missing linter is a host problem: the SessionStart probe reports it, and
  # reporting it at every turn end would not help. Only those lines are
  # dropped; any finding printed beside them is still reported.
  report=""
  while IFS= read -r line; do
    case "$line" in
    "FAIL: "*" missing. Install: "* | "To skip only while "*" is missing: "*) ;;
    *) report+="$line"$'\n' ;;
    esac
  done <<<"$err"
  # silent-skip-ok: only missing-tool lines remained, which the SessionStart probe reports.
  [[ -n "${report//[[:space:]]/}" ]] || exit 0
  err="${report%$'\n'}"
  if [[ "${CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_END_OF_TURN:-}" == true ]]; then
    printf '%s\n' "$err" >&2
    exit 2
  fi
  # shellcheck source=hook-utils.sh
  source "$HOOK_DIR/hook-utils.sh"
  hook::emit_system_message "$err"
  exit 0
fi

[[ "$INPUT" == *.md* ]] || exit 0
# silent-skip-ok: the SessionStart probe reports a missing jq (prerequisites.json)
command -v jq >/dev/null 2>&1 || exit 0
PATHS=$(jq -r '.tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit") | .tool_input.file_path? | strings | select(test("\\.(md|mdc)$"))' <<<"$INPUT" 2>/dev/null) || exit 0
[[ -n "$PATHS" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=../lib/git-hooks/resolve-tool.sh
source "$HOOK_DIR/../lib/git-hooks/resolve-tool.sh"
# shellcheck source=../git-hooks/markdown-gates.sh
source "$HOOK_DIR/../git-hooks/markdown-gates.sh"
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
  hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_LINT_GITIGNORED:-false}" "$file" && continue
  ROOTS+=("$root")
  FILES+=("$file")
done <<<"$PATHS"

# One run per repository root and resolved command, over all its files. The
# root is the working directory, so markdownlint-cli2's config discovery stops
# there whatever the session's cwd.
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
