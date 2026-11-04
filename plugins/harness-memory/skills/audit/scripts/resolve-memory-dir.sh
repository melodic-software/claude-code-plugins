#!/usr/bin/env bash
# Resolve the absolute path to the Claude Code auto-memory dir for the CURRENT project
# (a git repo, or the current directory outside one).
# The naive glob `~/.claude/projects/*/memory/` resolves alphabetical-first to the
# wrong repo on a multi-project machine; siblings call this instead of inlining it.

# No `set -e`: an optional git sub-command failing must not crash mid-resolve.
set -uo pipefail

# A pinned project directory name replaces the derived slug. These are this resolver's
# firing values, set to match the docs and the same check in session-flow's transcript_dirs.sh.
#   Pointer: https://code.claude.com/docs/en/sessions#name-the-project-directory-yourself
#   As of: 2026-11-04.
#   Recheck trigger: that section changes which values are accepted or when the variable applies.
pinned_memory_dir() {
  local pinned="${CLAUDE_CODE_PROJECT_DIR_NAME:-}"
  [[ -n "${CLAUDE_CONFIG_DIR:-}" && "$pinned" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || return 1
  case "$(printf '%s' "$pinned" | tr '[:upper:]' '[:lower:]')" in
  con | prn | aux | nul | com[0-9] | lpt[0-9]) return 1 ;;
  esac
  printf '%s\n' "$CLAUDE_CONFIG_DIR/projects/$pinned/memory"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
resolve-memory-dir.sh — emit absolute path to the auto-memory dir for the current project (repo or non-repo cwd).

Usage:
  resolve-memory-dir.sh [--help]

Derives the Claude Code project-dir slug from the repo root (repo-root absolute path,
Windows-style on Windows, with `:` `\` `/` `.` -> `-`) and prints the candidate dir that
holds MEMORY.md (handles bare-clone-hub worktrees). Outside a git repository the current
directory is the project key ("Outside a git repo, the project root is used instead").
A usable CLAUDE_CODE_PROJECT_DIR_NAME set beside CLAUDE_CONFIG_DIR names the directory instead.
EOF
  exit 0
fi

pinned_memory_dir && exit 0

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
