#!/usr/bin/env bash
# PostToolBatch hook: rewrite the Markdown files a batch of tool calls wrote.
#
#   markdown-format.sh                 the PostToolBatch row
#   markdown-format.sh --end-of-turn   the opt-in Stop row (markdown_format_end_of_turn)
#
# Rewrites only: `markdownlint-cli2 --fix`, once per batch over every .md and
# .mdc file a Write, Edit or MultiEdit in the batch named. It prints nothing and
# always exits 0, so no finding ever reaches the model per edit; findings are the
# pre-commit entry's job (git-hooks/markdown-check.sh), which also rewrites for
# every author.
#
# PostToolBatch has no matcher, so the row fires on every batch. The launcher
# skips the script unless the payload mentions ".md", and the script then reads
# tool_calls[].tool_input.file_path itself, so a batch with no Markdown edit costs
# one node process. A file that Read named is never rewritten.
#
# Opt-in: a file is rewritten only when a markdownlint config governs it and the
# config either cannot run repository code or runs it in a state the user
# approved (git-hooks/markdown-gates.sh holds both tests, shared with the
# pre-commit entry; an unapproved state is skipped silently here, and the
# pre-commit entry reports it). A repository without a config has
# chosen no Markdown style, so it is left untouched. markdownlint-cli2 comes from
# PATH or the repo's own node_modules/.bin, never downloaded. Files under
# .githooks/ are installed copies and are skipped, as are gitignored files
# unless markdown_format_lint_gitignored is true. The batch payload carries no
# pre-edit bytes, so a file that already drifted from the config is rewritten
# whole, as the pre-commit entry would.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :

# The opt-in Stop row: the pre-commit entry run over the uncommitted changes,
# without rewriting. Findings exit 2 so the model fixes them before the turn
# ends; once a Stop hook has continued the turn (stop_hook_active) the row stays
# quiet, so it blocks at most once per turn.
if [[ "${1:-}" == --end-of-turn ]]; then
  [[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
  err="$("${BASH:-bash}" "$HOOK_DIR/../git-hooks/markdown-check.sh" --worktree 2>&1 >/dev/null)" && exit 0
  # silent-skip-ok: the SessionStart probe already reports a missing markdownlint-cli2 (prerequisites.json) and /markdown-format:check does too; blocking every turn end on a host problem would not help the model.
  [[ "$err" == "FAIL: "*" missing. Install: "* ]] && exit 0
  printf '%s\n' "$err" >&2
  exit 2
fi

[[ "$INPUT" == *.md* ]] || exit 0
# silent-skip-ok: the SessionStart probe reports a missing jq (prerequisites.json)
command -v jq >/dev/null 2>&1 || exit 0
PATHS=$(jq -r '.tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit" or .tool_name == "MultiEdit") | .tool_input.file_path? | strings | select(test("\\.(md|mdc)$"))' <<<"$INPUT" 2>/dev/null) || exit 0
[[ -n "$PATHS" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=../git-hooks/markdown-gates.sh
source "$HOOK_DIR/../git-hooks/markdown-gates.sh"

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
  # Both sides physical, so a symlinked directory or checkout compares equal.
  pdir="$(cd "$dir" 2>/dev/null && pwd -P)" || continue
  proot="$(cd "$root" 2>/dev/null && pwd -P)" || continue
  md_config_state "$pdir/${file##*/}" "$proot"
  case "$MD_STATE" in
    plain) ;;
    code)
      md_trust "$proot"
      [[ "$MD_TRUST" == approved ]] || continue
      ;;
    *) continue ;;
  esac
  hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_LINT_GITIGNORED:-false}" "$file" && continue
  ROOTS+=("$proot")
  FILES+=(":$file")
done <<<"$PATHS"

# One run per repository root, over all its files. The root is the working
# directory so markdownlint-cli2's config discovery stops there whatever the
# session's cwd; the leading colon makes each argument a literal path, not a glob.
done_roots=$'\n'
for i in "${!ROOTS[@]}"; do
  root="${ROOTS[i]}"
  [[ "$done_roots" != *$'\n'"$root"$'\n'* ]] || continue
  done_roots+="$root"$'\n'
  group=()
  for j in "${!ROOTS[@]}"; do
    [[ "${ROOTS[j]}" == "$root" ]] && group+=("${FILES[j]}")
  done
  bin=markdownlint-cli2
  if ! command -v "$bin" >/dev/null 2>&1; then
    first="${group[0]#:}"
    bin="$(md_local_bin "${first%/*}" "$root")" || continue
  fi
  (cd "$root" && "$bin" --fix "${group[@]}") >/dev/null 2>&1 || :
done
exit 0
