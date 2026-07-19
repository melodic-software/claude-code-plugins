#!/usr/bin/env bash
# Resolve the absolute path to the Claude Code auto-memory dir for the CURRENT repo.
#
# Why this exists: the naive glob `~/.claude/projects/*/memory/` matches EVERY
# project's memory dir on a multi-project machine and resolves alphabetical-first
# to the wrong repo. This derives the project-dir slug from the repo root the same
# way Claude Code names its project dirs (repo-root absolute path, Windows-style on
# Windows, with `:` `\` `/` `.` -> `-`), then picks the candidate that actually holds
# MEMORY.md so bare-clone-hub worktrees (memory shared at the hub) resolve correctly.
#
# Single source of truth for memory-dir resolution within this plugin — sibling
# scripts and the audit workflow call this rather than inlining the glob.
#
# Usage (CWD-independent within the target repo):
#   MEMORY_DIR=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/resolve-memory-dir.sh")
#
# Output: absolute path to the memory dir (the dir containing MEMORY.md) on stdout.
# Exits 1 with a stderr message when not inside a git repo.

# `set -e` omitted: resolution does explicit error handling via `||` fallbacks and
# existence checks; must not crash mid-resolve on an optional git sub-command
# (e.g. --git-common-dir outside a worktree).
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
resolve-memory-dir.sh — emit absolute path to the auto-memory dir for the current repo.

Usage:
  resolve-memory-dir.sh [--help]

Derives the Claude Code project-dir slug from the repo root (repo-root absolute path,
Windows-style on Windows, with `:` `\` `/` `.` -> `-`) and prints the candidate dir that
holds MEMORY.md (handles bare-clone-hub worktrees). Exits 1 outside a git repository.
EOF
  exit 0
fi

# cygpath -w yields the Windows form on Git Bash (so `C:/...` not `/c/...`, which is
# how Claude Code names the project dir); falls back to raw rev-parse on macOS/Linux
# where cygpath does not exist. tr -d '\r' guards Git Bash CRLF on piped git output.
repo_root=$(cygpath -w "$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')" 2>/dev/null ||
  git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')

if [[ -z "$repo_root" ]]; then
  echo "resolve-memory-dir: not inside a git repository" >&2
  exit 1
fi

# sed (not tr) for path-char replacement — tr mishandles backslashes on Git Bash.
project_slug=$(printf '%s' "$repo_root" | sed 's/[:\\/.]/-/g')
session_data_dir="$HOME/.claude/projects/$project_slug"

# Bare-clone-hub worktree: transcripts are keyed by the worktree cwd, but auto-memory
# is shared at the HUB (keyed by git-common-dir). HUB_SLUG also maps '.' (e.g. a
# `/.bare` hub dir -> `--bare`). Decide by which candidate actually holds MEMORY.md —
# never by guessing the slug algorithm.
git_common=$(cd "$(git rev-parse --git-common-dir 2>/dev/null | tr -d '\r')" 2>/dev/null && pwd)
hub_raw=$(cygpath -w "$git_common" 2>/dev/null || printf '%s' "$git_common")
hub_slug=$(printf '%s' "$hub_raw" | sed 's/[:\\/.]/-/g')

memory_dir=""
for cand in "$session_data_dir/memory" "$HOME/.claude/projects/$hub_slug/memory"; do
  if [[ -f "$cand/MEMORY.md" ]]; then
    memory_dir="$cand"
    break
  fi
done

# Fresh repo with no memory written yet: emit the normal-clone path so callers have a
# stable target (MEMORY.md absence is handled downstream by the caller).
[[ -z "$memory_dir" ]] && memory_dir="$session_data_dir/memory"

printf '%s\n' "$memory_dir"
