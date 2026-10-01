#!/usr/bin/env bash
# Parse an issue number from a branch name following the convention
# `<type>/<N>-<slug>` or the cloud-routine variant `<type>/routine-issue-<N>-<slug>`.
#
# Usage:
#   parse-branch-issue.sh [branch-name]
#
# With no arg, falls back to `git branch --show-current`.
# Prints the captured issue number on stdout and exits 0 on match.
# Exits 1 with no output if the branch lacks an issue number.
set -uo pipefail

BRANCH="${1:-}"
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
fi

if [[ -z "$BRANCH" ]]; then
  exit 1
fi

if [[ "$BRANCH" =~ ^[a-z]+/(routine-issue-)?([0-9]+)- ]]; then
  echo "${BASH_REMATCH[2]}"
  exit 0
fi

exit 1
