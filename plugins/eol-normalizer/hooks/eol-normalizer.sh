#!/usr/bin/env bash
# PostToolBatch hook: normalize the line endings of the files a batch of tool
# calls wrote to each file's .gitattributes `eol=` value (symmetric, driven by
# `git check-attr`).
#
# Rewrites only: it prints nothing and always exits 0, so no message reaches the
# model or the user. There is no pre-commit entry. `git add` applies the same
# attributes to the bytes it stores (a CRLF file under `eol=lf` and an LF file
# under `eol=crlf` are both indexed as LF), so a commit never carries the wrong
# ending; what this hook fixes is the working tree, where a CRLF shell script
# fails to run and an `eol=crlf` file reads as drifted until it is rewritten.
#
# PostToolBatch has no matcher, so the row fires on every batch. The launcher
# skips the script unless the payload mentions "file_path", and the script then
# returns at once unless a Write, Edit or MultiEdit is in the batch, so a batch
# that only ran Bash costs one node process and one that only Read a file costs
# that plus one bash. A file that Read named is never rewritten.
#
# No glob list: the row's tool filter is the only filter, because which files
# carry line endings the repository governs is the consuming repository's
# .gitattributes to say. Resolution is `git check-attr`, anchored at the file's
# own directory, so it is correct for clones, linked worktrees and bare-hub
# clones, and does not depend on the hook's working directory.
#
# Files under .githooks/ are installed copies and are skipped, as are gitignored
# files unless eol_normalizer_lint_gitignored is true (the check costs a git
# process, so it runs only for a file that has something to rewrite).

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :

[[ "$INPUT" == *'"Write"'* || "$INPUT" == *'Edit"'* ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0  # silent-skip-ok: the SessionStart prerequisites probe reports a missing jq; this hook is silent by design
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
  # Existence, symlink and project membership, as for a single-file hook.
  hook::read_file_path_to file "{\"tool_input\":{\"file_path\":\"$escaped\"}}" || continue
  [[ "$file" == */.githooks/* ]] && continue
  hook::dirname_to dir "$file"
  plan=$(normalize_eol_plan "$dir" "$file")
  [[ "${plan##* }" == 1 ]] || continue
  hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_LINT_GITIGNORED:-false}" "$file" && continue
  normalize_eol_apply "${plan%% *}" "$file"
done <<<"$PATHS"
exit 0
