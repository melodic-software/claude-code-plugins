#!/usr/bin/env bash
# changed-code-files.sh — list uncommitted code files for the audit-comment-residue
# and dissolve-comments skills' `## Pre-computed context` blocks.
#
# The awk body this replaces sat inline in each SKILL.md, and skill argument
# substitution rewrites `$<digit>` placeholders anywhere in a skill's file body
# (0-based: `$0` is the first argument), so any invocation carrying an argument
# corrupted the probe's `substr($0, …)` calls before the shell ever ran. A script
# reached through `${CLAUDE_PLUGIN_ROOT}` keeps the awk outside the substitution
# surface, and removes the inline `$`-expansion the worktree-isolation guard
# refuses (#1687). Shared at the plugin level because both callers need the
# identical listing.
#
# Usage: changed-code-files.sh [max]
#   max — cap on emitted paths (default 10)
#
# Output: up to <max> repo-relative paths of changed or untracked code files, one
# per line, in `git status` order; empty when nothing matches. Rename and copy
# entries emit the new path only. Exit 1 when git status is unavailable; callers
# supply their own fallback text.
set -u

MAX="${1:-10}"

git status --porcelain -z >/dev/null 2>&1 || exit 1

git status --porcelain -z 2>/dev/null |
  awk 'BEGIN { RS = "\0" } skip { skip = 0; next } { if (substr($0, 1, 2) ~ /[RC]/) skip = 1; print substr($0, 4) }' |
  grep -Ei '\.(cs|ts|tsx|js|jsx|py|sh|ps1|go|rs|java|rb|lua|sql|c|h|cpp|hpp|yaml|yml|toml)$' |
  head -n "$MAX"
exit 0
