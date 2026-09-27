#!/usr/bin/env bash
# discover-instruction-surfaces.sh — enumerate the CLAUDE.md, AGENTS.md and rules files in
# audit scope, each tagged with the scope it loads from.
# Exists because a bare `find` from the current directory never sees the user-global
# surfaces, which load in every session; the scope tag keeps project-only criteria off them.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/agents-md.sh
source "$SCRIPT_DIR/lib/agents-md.sh"

SCOPE_FILTER="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    cat <<'EOF'
discover-instruction-surfaces.sh — list in-scope CLAUDE.md and rules files with their scope tag.

Usage: discover-instruction-surfaces.sh [--scope project|user|all] [--help]

Emits one TAB-separated record per file: <scope> <kind> <path>

  scope   project  — CLAUDE.md / CLAUDE.local.md / AGENTS.md / .claude/AGENTS.md at the
                     current root, and .claude/rules/*.md
          user     — ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md and .../rules/*.md
          both     — one physical file both layers reach (a repo rooted at ~, or one
                     rooted at ~/.claude itself). Emitted once, not twice.
  kind    claude-md | claude-local-md | agents-md | rule

An AGENTS.md is emitted only where Claude Code reads it as the project instructions: no
CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md in the root or any directory above it to
displace it (the user root's own ~/.claude/CLAUDE.md does not count). Both AGENTS.md
and .claude/AGENTS.md load at session start, so each existing file gets its own row. Under
a one-line `@AGENTS.md` shim the CLAUDE.md row already covers that content, so the shim
emits one row, not two.

User-scope files load in EVERY session regardless of where the session starts, so they are
in audit scope. They are tagged so project-scoped criteria (C9) can skip them rather than
reporting a repo-scoped finding against a personal file.

Always exits 0. A surface that does not exist is simply not emitted.
EOF
    exit 0
    ;;
  --scope)
    shift
    SCOPE_FILTER="${1:-all}"
    ;;
  *)
    printf 'discover-instruction-surfaces.sh: unknown argument: %s\n' "$1" >&2
    exit 0
    ;;
  esac
  shift
done

emit() {
  local scope="$1" kind="$2" path="$3"
  # A `both` record satisfies every filter: the file really is reachable by each layer,
  # so suppressing it from either view would hide a surface that view is about.
  case "$SCOPE_FILTER" in
  all) ;;
  "$scope") ;;
  *) [[ "$scope" == "both" ]] || return 0 ;;
  esac
  printf '%s\t%s\t%s\n' "$scope" "$kind" "$path"
}

emit_rules() {
  local rules_dir="$1" scope="$2"
  while IFS= read -r rule; do
    [[ -n "$rule" ]] && emit "$scope" rule "$rule"
  done < <(find "$rules_dir" -name "*.md" -type f 2>/dev/null | LC_ALL=C sort)
}

canon_dir() {
  [[ -d "$1" ]] || return 0
  (cd "$1" 2>/dev/null && pwd -P) || true
}

# Avoids readlink -f, which is absent on some platforms.
canon_file() {
  [[ -f "$1" ]] || return 0
  local d b
  d="$(canon_dir "$(dirname "$1")")"
  [[ -n "$d" ]] || return 0
  b="$(basename "$1")"
  printf '%s/%s' "$d" "$b"
}

# A file both scopes reach is emitted once as `both`. A `~`-rooted repo collides only the
# rules dir and a `~/.claude`-rooted repo only CLAUDE.md, so each comparison is independent.
config_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

proj_rules_canon="$(canon_dir ".claude/rules")"
user_rules_canon="$(canon_dir "$config_root/rules")"

rules_overlap=0
if [[ -n "$proj_rules_canon" && "$proj_rules_canon" == "$user_rules_canon" ]]; then
  rules_overlap=1
fi

proj_md_canon="$(canon_file "CLAUDE.md")"
user_md_canon="$(canon_file "$config_root/CLAUDE.md")"

md_overlap=0
if [[ -n "$proj_md_canon" && "$proj_md_canon" == "$user_md_canon" ]]; then
  md_overlap=1
fi

# Depth 1 by design: CLAUDE.md files nested deeper are subtree memory that loads only
# on demand, and are not this checklist's subject.

if [[ -f "CLAUDE.md" ]]; then
  proj_md_scope=project
  [[ "$md_overlap" -eq 1 ]] && proj_md_scope=both
  emit "$proj_md_scope" claude-md "CLAUDE.md"
fi
[[ -f "CLAUDE.local.md" ]] && emit project claude-local-md "CLAUDE.local.md"
while IFS= read -r agents_file; do
  [[ -n "$agents_file" ]] && emit project agents-md "$agents_file"
done < <(agents_md_native_files)

if [[ -d ".claude/rules" ]]; then
  proj_rule_scope=project
  [[ "$rules_overlap" -eq 1 ]] && proj_rule_scope=both
  emit_rules ".claude/rules" "$proj_rule_scope"
fi

if [[ -d "$config_root" ]]; then
  # An overlapping file or rules dir was already emitted above as `both`.
  if [[ -f "$config_root/CLAUDE.md" && "$md_overlap" -eq 0 ]]; then
    emit user claude-md "$config_root/CLAUDE.md"
  fi

  if [[ -d "$config_root/rules" && "$rules_overlap" -eq 0 ]]; then
    emit_rules "$config_root/rules" user
  fi
fi

exit 0
