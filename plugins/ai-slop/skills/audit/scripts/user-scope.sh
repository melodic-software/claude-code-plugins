#!/usr/bin/env bash
# List the user-level Claude Code markdown the audit's `user-scope` target
# covers: one absolute path per line, sorted, ready for
# `detect.sh --list-targets --paths-file`.
#
# The surfaces are the user-level markdown files named in
# https://code.claude.com/docs/en/claude-directory, under CLAUDE_CONFIG_DIR
# when it is set and non-empty, else $HOME/.claude:
#   CLAUDE.md
#   rules/**/*.md
#   skills/<name>/**/*.md, for each <name> directory holding SKILL.md
#   commands/**/*.md
#   agents/**/*.md
#   output-styles/*.md (top level only)
# --memory adds projects/*/memory/*.md and agent-memory/*/*.md.
#
# Symlinks are followed. Only readable regular files are listed, and none is
# opened, so a FIFO cannot stall the listing. A path holding a newline is
# skipped with a warning on stderr.
#
# Exit: 0 ok, including an empty list; 2 on a usage error or a missing root.
set -u
export LC_ALL=C
ME="user-scope.sh"

usage() {
  cat <<'EOF'
user-scope.sh: list user-level Claude Code markdown for /ai-slop:audit.

Usage:
  user-scope.sh [--memory] [--help]

Root: CLAUDE_CONFIG_DIR when set and non-empty, else $HOME/.claude.
Lists CLAUDE.md, rules/**, skills/<name>/** (where SKILL.md exists),
commands/**, agents/**, and output-styles/*.md; --memory adds
projects/*/memory/*.md and agent-memory/*/*.md.
Exit: 0 ok, 2 usage error or missing root.
EOF
}

memory=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  --memory) memory=1 ;;
  --help | -h) usage; exit 0 ;;
  *) echo "$ME: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

root="${CLAUDE_CONFIG_DIR:-}"
if [[ -z "$root" ]]; then
  [[ -n "${HOME:-}" ]] || { echo "$ME: neither CLAUDE_CONFIG_DIR nor HOME is set" >&2; exit 2; }
  root="$HOME/.claude"
fi
[[ -d "$root" ]] || { echo "$ME: config root not found: $root" >&2; exit 2; }
root="$(CDPATH='' cd -- "$root" && pwd)" || { echo "$ME: cannot enter config root: $root" >&2; exit 2; }

# collect <start> [find options]: every readable regular *.md file under start.
collect() {
  local p
  [[ -d "$1" ]] || return 0
  while IFS= read -r -d '' p; do
    if [[ "$p" == *$'\n'* ]]; then
      printf '%s: skipped a path holding a newline: %q\n' "$ME" "$p" >&2
      continue
    fi
    [[ -f "$p" && -r "$p" ]] && printf '%s\n' "$p"
  done < <(find -L "$1" "${@:2}" -type f -name '*.md' -print0)
}

list() {
  local d
  collect "$root" -maxdepth 1 -name CLAUDE.md
  collect "$root/rules"
  for d in "$root"/skills/*/; do
    [[ -f "${d}SKILL.md" ]] && collect "${d%/}"
  done
  collect "$root/commands"
  collect "$root/agents"
  collect "$root/output-styles" -maxdepth 1
  if [[ "$memory" == 1 ]]; then
    for d in "$root"/projects/*/memory; do collect "$d" -maxdepth 1; done
    for d in "$root"/agent-memory/*/; do collect "${d%/}" -maxdepth 1; done
  fi
}

out="$(list | sort)"
if [[ -z "$out" ]]; then
  echo "$ME: no user-scope markdown under $root" >&2
  exit 0
fi
printf '%s\n' "$out"
