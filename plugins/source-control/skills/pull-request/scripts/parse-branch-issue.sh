#!/usr/bin/env bash
# Parse the (numeric GitHub) issue number from a branch name. The default
# convention is `<type>/<N>-<slug>` (or the cloud-routine variant
# `<type>/routine-issue-<N>-<slug>`), but the grammar is configurable so a
# consumer whose branches place the number differently — e.g. a username-scoped
# scheme `alice/1234-slug` or a trailing-number scheme `feat/add-widget-1234` —
# is not silently unparsable.
#
# Usage:
#   parse-branch-issue.sh [branch-name] [pattern]
#
# With no branch arg, falls back to `git branch --show-current`.
# `pattern` is an ERE whose LAST capture group holds the issue id; it must
# resolve to the numeric GitHub issue number (the caller emits `Closes #<id>`,
# which GitHub honors only for a numeric issue in this repo — a non-numeric
# capture is looked up, found absent, and dropped). When omitted, `pattern`
# falls back to the branch_issue_pattern userConfig
# (CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN, when a caller exports it) and then
# the built-in default.
# Prints the captured issue id on stdout and exits 0 on match.
# Exits 1 with no output if the branch does not match.
set -uo pipefail

BRANCH="${1:-}"
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
fi

if [[ -z "$BRANCH" ]]; then
  exit 1
fi

# A surviving literal `${user_config...}` placeholder means the key is unset —
# treat it as absent so the default applies rather than a bogus pattern.
PATTERN="${2:-}"
# shellcheck disable=SC2016  # matching the literal placeholder text, not expanding it
[[ "$PATTERN" == *'${user_config'* ]] && PATTERN=""
[[ -n "$PATTERN" ]] || PATTERN="${CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN:-}"
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
