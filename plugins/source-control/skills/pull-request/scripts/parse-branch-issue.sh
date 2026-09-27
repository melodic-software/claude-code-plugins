#!/usr/bin/env bash
# Parse the (numeric GitHub) issue number from a branch name. The default
# convention is `<type>/<N>-<slug>` (or the cloud-routine variant
# `<type>/routine-issue-<N>-<slug>`), but the grammar is configurable so a
# consumer whose branches place the number differently, e.g. a username-scoped
# scheme `alice/1234-slug` or a trailing-number scheme `feat/add-widget-1234`,
# is not silently unparsable.
#
# Usage:
#   parse-branch-issue.sh [branch-name] [pattern]
#
# With no branch arg, falls back to `git branch --show-current`.
# The grammar is an ERE whose LAST capture group holds the issue id; it must
# resolve to the numeric GitHub issue number (the caller emits `Closes #<id>`,
# which GitHub honors only for a numeric issue in this repo; a non-numeric
# capture is looked up, found absent, and dropped). It resolves, first hit wins:
#   1. The `## branch_issue_pattern` section of the layered
#      `.claude/source-control.md` surface (reference/config-resolution.md):
#      `<repo>/.claude/source-control.local.md` over
#      `<repo>/.claude/source-control.md` over `$HOME/.claude/source-control.md`.
#      The value is the section's first non-blank line, surrounding backticks
#      stripped. Repo root: CLAUDE_PROJECT_DIR, else `git rev-parse --show-toplevel`.
#   2. The deprecated branch_issue_pattern userConfig: `pattern` (unless it is the
#      literal `${user_config...}` placeholder), then
#      CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN. Using it prints a deprecation
#      note on stderr.
#   3. The built-in default.
# A layer holding an invalid ERE is reported on stderr and skipped.
# Prints the captured issue id on stdout and exits 0 on match.
# Exits 1 with no stdout if the branch does not match.
set -uo pipefail

KEY="branch_issue_pattern"

BRANCH="${1:-}"
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
fi

if [[ -z "$BRANCH" ]]; then
  exit 1
fi

# Print the first non-blank line of the `## branch_issue_pattern` section of
# file $1, surrounding whitespace and backticks stripped. Prints nothing when
# the file or the section is absent.
section_value() {
  local file="$1" line in_section=0
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" =~ ^##[[:space:]] ]]; then
      [[ "$in_section" -eq 1 ]] && return 0
      [[ "$line" =~ ^##[[:space:]]+${KEY}[[:space:]]*$ ]] && in_section=1
      continue
    fi
    [[ "$in_section" -eq 1 ]] || continue
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    while [[ "$line" == \`* ]]; do line="${line#\`}"; done
    while [[ "$line" == *\` ]]; do line="${line%\`}"; done
    printf '%s\n' "$line"
    return 0
  done <"$file"
}

# True when $1 compiles as an ERE; bash's =~ returns 2 on a bad pattern.
valid_ere() {
  [[ "" =~ $1 ]]
  [[ $? -ne 2 ]]
}

REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
[[ -n "$REPO_ROOT" ]] || REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

LAYERS=()
[[ -n "$REPO_ROOT" ]] && LAYERS+=("${REPO_ROOT}/.claude/source-control.local.md" "${REPO_ROOT}/.claude/source-control.md")
LAYERS+=("${HOME:-}/.claude/source-control.md")

PATTERN=""
for layer in "${LAYERS[@]}"; do
  value="$(section_value "$layer")"
  [[ -n "$value" ]] || continue
  if valid_ere "$value"; then
    PATTERN="$value"
    break
  fi
  echo "parse-branch-issue: skipping invalid ERE in ${layer} ## ${KEY}: ${value}" >&2
done

if [[ -z "$PATTERN" ]]; then
  # A surviving literal `${user_config...}` placeholder means the key is unset;
  # treat it as absent so the default applies rather than a bogus pattern.
  LEGACY="${2:-}"
  # shellcheck disable=SC2016  # matching the literal placeholder text, not expanding it
  [[ "$LEGACY" == *'${user_config'* ]] && LEGACY=""
  [[ -n "$LEGACY" ]] || LEGACY="${CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN:-}"
  if [[ -n "$LEGACY" ]]; then
    PATTERN="$LEGACY"
    echo "parse-branch-issue: the branch_issue_pattern userConfig is deprecated; set a \`## ${KEY}\` section in .claude/source-control.md instead." >&2
  fi
fi
[[ -n "$PATTERN" ]] || PATTERN='^[a-z]+/(routine-issue-)?([0-9]+)-'

if [[ "$BRANCH" =~ $PATTERN ]]; then
  # Issue id = the last (rightmost) capture group, so the default pattern's
  # optional leading group still resolves to the trailing number, and a custom
  # single-group pattern resolves to its one group.
  n=${#BASH_REMATCH[@]}
  echo "${BASH_REMATCH[n - 1]}"
  exit 0
fi

exit 1
