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
# which GitHub honors only for a numeric issue in this repo). A pattern with
# no capture group, or a capture that is not all digits, yields no output and
# exit 1. It resolves, first hit wins:
#   1. The `## branch_issue_pattern` section of the layered
#      `.claude/source-control.md` surface (reference/config-resolution.md):
#      `<repo>/.claude/source-control.local.md` over
#      `<repo>/.claude/source-control.md` over `$HOME/.claude/source-control.md`.
#      The value is the section's first non-blank line, surrounding backticks
#      stripped, or, when that line opens a code fence, the first non-blank line
#      inside the fence. Headings inside fenced blocks are ignored. Repo root:
#      CLAUDE_PROJECT_DIR, else `git rev-parse --show-toplevel`.
#   2. The deprecated branch_issue_pattern userConfig: `pattern` (unless it is the
#      literal `${user_config...}` placeholder), then
#      CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN. Using it prints a deprecation
#      note on stderr.
#   3. The built-in default.
# A layer holding an invalid ERE, a backreference, or an empty or unterminated
# fence is reported on stderr and skipped; an invalid or backreferencing
# userConfig value is reported and ignored. Notes name the source and the
# reason, never the pattern text.
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

# Notes name the source and the reason only, never the pattern text, so a
# repo-controlled value is not echoed into the caller's context.
note() { echo "parse-branch-issue: $*" >&2; }

FENCE_OPEN='^(```+|~~~+)'
FENCE_CLOSE='^(```+|~~~+)$'

# Print the value of the `## branch_issue_pattern` section of file $1: its first
# non-blank line, surrounding whitespace and backticks stripped, or, when that
# line opens a code fence, the first non-blank line inside the fence. Headings
# inside fenced blocks are ignored. Prints nothing when the file or the section
# is absent; an empty or unterminated fence is reported and prints nothing.
section_value() {
  local file="$1" line in_section=0 fence=""
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ -n "$fence" ]]; then
      if [[ "$line" =~ $FENCE_CLOSE && "${line:0:1}" == "${fence:0:1}" && ${#line} -ge ${#fence} ]]; then
        if [[ "$in_section" -eq 1 ]]; then
          note "${file}: ## ${KEY} holds an empty code fence; layer skipped"
          return 0
        fi
        fence=""
      elif [[ "$in_section" -eq 1 && -n "$line" ]]; then
        printf '%s\n' "$line"
        return 0
      fi
      continue
    fi
    if [[ "$line" =~ ^##[[:space:]] ]]; then
      [[ "$in_section" -eq 1 ]] && return 0
      [[ "$line" =~ ^##[[:space:]]+${KEY}$ ]] && in_section=1
      continue
    fi
    if [[ "$line" =~ $FENCE_OPEN ]]; then
      fence="${BASH_REMATCH[1]}"
      continue
    fi
    [[ "$in_section" -eq 1 && -n "$line" ]] || continue
    while [[ "$line" == \`* ]]; do line="${line#\`}"; done
    while [[ "$line" == *\` ]]; do line="${line%\`}"; done
    printf '%s\n' "$line"
    return 0
  done <"$file"
  [[ -n "$fence" && "$in_section" -eq 1 ]] && note "${file}: ## ${KEY} holds an unterminated code fence; layer skipped"
  return 0
}

# True when pattern $2 from source $1 is usable: it compiles as an ERE (bash's
# =~ returns 2 on a bad pattern) and holds no backreference. Otherwise reports
# the source and the reason.
usable_pattern() {
  local src="$1" value="$2" rc
  if [[ "$value" =~ \\[1-9] ]]; then
    note "${src}: ${KEY} uses a backreference, which is not allowed; skipped"
    return 1
  fi
  { [[ "" =~ $value ]]; } 2>/dev/null
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    note "${src}: ${KEY} is an invalid ERE; skipped"
    return 1
  fi
  return 0
}

REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
[[ -n "$REPO_ROOT" ]] || REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

LAYERS=()
[[ -n "$REPO_ROOT" ]] && LAYERS+=("${REPO_ROOT}/.claude/source-control.local.md" "${REPO_ROOT}/.claude/source-control.md")
LAYERS+=("${HOME:-}/.claude/source-control.md")

PATTERN="" SOURCE=""
for layer in "${LAYERS[@]}"; do
  value="$(section_value "$layer")"
  [[ -n "$value" ]] || continue
  if usable_pattern "$layer" "$value"; then
    PATTERN="$value" SOURCE="$layer"
    break
  fi
done

if [[ -z "$PATTERN" ]]; then
  # A surviving literal `${user_config...}` placeholder means the key is unset;
  # treat it as absent so the default applies rather than a bogus pattern.
  LEGACY="${2:-}"
  # shellcheck disable=SC2016  # matching the literal placeholder text, not expanding it
  [[ "$LEGACY" == *'${user_config'* ]] && LEGACY=""
  [[ -n "$LEGACY" ]] || LEGACY="${CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN:-}"
  if [[ -n "$LEGACY" ]] && usable_pattern userConfig "$LEGACY"; then
    PATTERN="$LEGACY" SOURCE="userConfig"
    note "the ${KEY} userConfig is deprecated; set a \`## ${KEY}\` section in .claude/source-control.md instead."
  fi
fi
[[ -n "$PATTERN" ]] || PATTERN='^[a-z]+/(routine-issue-)?([0-9]+)-' SOURCE="default"

[[ "$BRANCH" =~ $PATTERN ]] || exit 1

# Issue id = the last (rightmost) capture group, so the default pattern's
# optional leading group still resolves to the trailing number, and a custom
# single-group pattern resolves to its one group.
n=${#BASH_REMATCH[@]}
if [[ "$n" -lt 2 ]]; then
  note "${SOURCE}: ${KEY} has no capture group; no issue id emitted"
  exit 1
fi
id="${BASH_REMATCH[n - 1]}"
if [[ ! "$id" =~ ^[0-9]+$ ]]; then
  note "${SOURCE}: ${KEY} captured a non-numeric id; no issue id emitted"
  exit 1
fi
echo "$id"
