#!/usr/bin/env bash
# Resolve the absolute path to the Claude Code auto-memory dir for the CURRENT project
# (a git repo, or the current directory outside one).
# The naive glob `~/.claude/projects/*/memory/` resolves alphabetical-first to the
# wrong repo on a multi-project machine; siblings call this instead of inlining it.

# No `set -e`: an optional git sub-command failing must not crash mid-resolve.
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
resolve-memory-dir.sh — emit absolute path to the auto-memory dir for the current project (repo or non-repo cwd).

Usage:
  resolve-memory-dir.sh [--help]

Derives the Claude Code project-dir slug from the repo root (repo-root absolute path,
Windows-style on Windows, with `:` `\` `/` `.` -> `-`) and prints the candidate dir that
holds MEMORY.md (handles bare-clone-hub worktrees). Outside a git repository the current
directory is the project key ("Outside a git repo, the project root is used instead").
EOF
  exit 0
fi

# tr -d '\r' strips Git Bash CRLF from piped git output. cygpath -w then yields the
# Windows form Claude Code names project dirs with, falling back to the raw path where
# cygpath does not exist.
repo_root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
if [[ -n "$repo_root" ]]; then
  repo_root=$(cygpath -w "$repo_root" 2>/dev/null || printf '%s' "$repo_root")
fi

# Outside a git repo the cwd is the project key (memory doc).
in_repo=1
if [[ -z "$repo_root" ]]; then
  in_repo=0
  repo_root=$(cygpath -w "$(pwd)" 2>/dev/null || pwd)
fi

config_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# sed (not tr) for path-char replacement — tr mishandles backslashes on Git Bash.
project_slug=$(printf '%s' "$repo_root" | sed 's/[:\\/.]/-/g')
session_data_dir="$config_root/projects/$project_slug"

# A bare-clone-hub worktree shares auto-memory at the hub (git-common-dir): pick the
# candidate that actually holds MEMORY.md rather than guessing the slug algorithm.
memory_dir=""
if [[ "$in_repo" -eq 1 ]]; then
  git_common=$(cd "$(git rev-parse --git-common-dir 2>/dev/null | tr -d '\r')" 2>/dev/null && pwd)
  hub_raw=$(cygpath -w "$git_common" 2>/dev/null || printf '%s' "$git_common")
  hub_slug=$(printf '%s' "$hub_raw" | sed 's/[:\\/.]/-/g')

  for cand in "$session_data_dir/memory" "$config_root/projects/$hub_slug/memory"; do
    if [[ -f "$cand/MEMORY.md" ]]; then
      memory_dir="$cand"
      break
    fi
  done
fi

# No memory written yet: emit the normal-clone path so callers have a stable target.
[[ -z "$memory_dir" ]] && memory_dir="$session_data_dir/memory"

printf '%s\n' "$memory_dir"
