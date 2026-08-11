#!/usr/bin/env bash
# discover-instruction-surfaces.sh — enumerate the CLAUDE.md and rules files in audit scope,
# each tagged with the scope it loads from.
#
# Why this exists: Step 1 discovery used to be two bare `find` commands rooted at the
# current directory (`find . -maxdepth 1 -name CLAUDE.md`, `find .claude/rules ...`), so it
# could only ever see PROJECT-scope files. The user-global surfaces — `~/.claude/CLAUDE.md`
# and `~/.claude/rules/*.md` — load in every session and were reachable by neither this
# skill nor `claude-config:audit-instructions`, whose surface partition explicitly hands
# `~/.claude/rules/` here by name. One skill delegated a user-global surface; the receiving
# skill's discovery could not reach it, so nothing audited it.
#
# Scope tagging is not cosmetic. Several criteria are project-scoped (C9 is the live case),
# and widening discovery WITHOUT a scope field would make them fire on personal files that
# are out of their remit — trading under-coverage for false positives. The caller routes on
# the emitted scope rather than guessing from the path shape.
#
# Config root honors CLAUDE_CONFIG_DIR the same way the sibling resolver does: per the
# official .claude-directory doc, setting it relocates every `~/.claude` path.
#
# Advisory: prints what it finds, ALWAYS exits 0. A missing surface is not an error —
# most repos have no CLAUDE.local.md and many machines have no user-scope CLAUDE.md.
#
# Usage:
#   discover-instruction-surfaces.sh              # TAB-separated: <scope> <kind> <path>
#   discover-instruction-surfaces.sh --scope user # only the user-scope surfaces
#   discover-instruction-surfaces.sh --help
#
# Output columns:
#   scope  project | user
#   kind   claude-md | claude-local-md | rule
#   path   absolute for user scope, as-found for project scope

set -uo pipefail

SCOPE_FILTER="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    cat <<'EOF'
discover-instruction-surfaces.sh — list in-scope CLAUDE.md and rules files with their scope tag.

Usage: discover-instruction-surfaces.sh [--scope project|user|all] [--help]

Emits one TAB-separated record per file: <scope> <kind> <path>

  scope   project  — CLAUDE.md / CLAUDE.local.md at the current root, and .claude/rules/*.md
          user     — ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md and .../rules/*.md
  kind    claude-md | claude-local-md | rule

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
  # $1 scope, $2 kind, $3 path
  case "$SCOPE_FILTER" in
  all) ;;
  "$1") ;;
  *) return 0 ;;
  esac
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

# --- project scope -----------------------------------------------------------
# Depth 1 by design: CLAUDE.md files nested deeper are subtree memory that loads only
# on demand, and are not this checklist's subject.

[[ -f "CLAUDE.md" ]] && emit project claude-md "CLAUDE.md"
[[ -f "CLAUDE.local.md" ]] && emit project claude-local-md "CLAUDE.local.md"

if [[ -d ".claude/rules" ]]; then
  while IFS= read -r rule; do
    [[ -n "$rule" ]] && emit project rule "$rule"
  done < <(find ".claude/rules" -name "*.md" -type f 2>/dev/null | LC_ALL=C sort)
fi

# --- user scope --------------------------------------------------------------
# Same resolution as resolve-memory-dir.sh: CLAUDE_CONFIG_DIR relocates the whole
# `~/.claude` tree when set, so the instruction surfaces move with it.
config_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

if [[ -n "$config_root" && -d "$config_root" ]]; then
  [[ -f "$config_root/CLAUDE.md" ]] && emit user claude-md "$config_root/CLAUDE.md"

  if [[ -d "$config_root/rules" ]]; then
    while IFS= read -r rule; do
      [[ -n "$rule" ]] && emit user rule "$rule"
    done < <(find "$config_root/rules" -name "*.md" -type f 2>/dev/null | LC_ALL=C sort)
  fi
fi

exit 0
