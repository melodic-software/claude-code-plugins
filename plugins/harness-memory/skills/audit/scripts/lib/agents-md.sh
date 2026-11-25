#!/usr/bin/env bash
agents_md_is_user_root() {
  local d="$1"
  [[ -n "${HOME:-}" && -d "$HOME/.claude" && "$d" -ef "$HOME/.claude" ]] && return 0
  [[ -n "${CLAUDE_CONFIG_DIR:-}" && -d "$CLAUDE_CONFIG_DIR" && "$d" -ef "$CLAUDE_CONFIG_DIR" ]]
}

agents_md_displaced() {
  local dir="$PWD" parent
  while :; do
    [[ -f "$dir/CLAUDE.md" || -f "$dir/CLAUDE.local.md" ]] && return 0
    if [[ -f "$dir/.claude/CLAUDE.md" ]]; then
      agents_md_is_user_root "$dir/.claude" || return 0
    fi
    parent="$(dirname "$dir")"
    [[ "$parent" == "$dir" ]] && return 1
    dir="$parent"
  done
}

agents_md_native_files() {
  agents_md_displaced && return 0
  local f
  for f in AGENTS.md .claude/AGENTS.md; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
  return 0
}
