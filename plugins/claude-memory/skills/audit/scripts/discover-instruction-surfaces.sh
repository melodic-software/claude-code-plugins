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
#   scope  project | user | both
#   kind   claude-md | claude-local-md | rule
#   path   absolute for user scope, as-found for project scope
#
# `both` means one PHYSICAL file that both layers reach. Two dotfiles layouts do this,
# each colliding exactly one surface: a repo rooted at `~` collides the RULES dir
# (`.claude/rules` IS `~/.claude/rules`), and a repo rooted at `~/.claude` itself
# collides CLAUDE.md (the depth-1 `CLAUDE.md` IS `~/.claude/CLAUDE.md`). Such a file is
# emitted once, never twice under two path spellings, so it cannot produce a duplicate
# finding or be compared against itself in the cross-scope pass.

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
          both     — one physical file both layers reach (a repo rooted at ~, or one
                     rooted at ~/.claude itself). Emitted once, not twice.
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
  # A `both` record satisfies every filter: the file really is reachable by each layer,
  # so suppressing it from either view would hide a surface that view is about.
  case "$SCOPE_FILTER" in
  all) ;;
  "$1") ;;
  *) [[ "$1" == "both" ]] || return 0 ;;
  esac
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

emit_rules() {
  # $1 rules dir, $2 scope
  while IFS= read -r rule; do
    [[ -n "$rule" ]] && emit "$2" rule "$rule"
  done < <(find "$1" -name "*.md" -type f 2>/dev/null | LC_ALL=C sort)
}

# Canonical physical path of a directory, or empty when it does not resolve.
# `pwd -P` because two dirs can be the SAME directory reached by two different
# strings — see the overlap note below.
canon_dir() {
  [[ -d "$1" ]] || return 0
  (cd "$1" 2>/dev/null && pwd -P) || true
}

# Canonical physical path of a FILE, or empty. Resolves the containing directory and
# re-appends the basename, so it works without readlink -f (absent on some platforms).
canon_file() {
  [[ -f "$1" ]] || return 0
  local d b
  d="$(canon_dir "$(dirname "$1")")"
  [[ -n "$d" ]] || return 0
  b="$(basename "$1")"
  printf '%s/%s' "$d" "$b"
}

# --- scope overlap -----------------------------------------------------------
# Two dotfiles layouts make a project-scope path and a user-scope path the SAME physical
# file. Emitting such a file twice under two path strings would produce a duplicate
# finding and a cross-scope comparison of a file against itself, so wherever the
# canonical paths coincide the file is emitted ONCE with scope `both`.
#
# Each layout collides exactly ONE of the two surfaces, which is why both guards below
# are needed and neither can be argued away from the other:
#
#   1. Project root IS the home directory (a `~`-rooted dotfiles repo — the shape the
#      sibling audit-pass contract calls an ordinary target).
#        rules:     `.claude/rules` == `<config_root>/rules`          -> COLLIDES
#        CLAUDE.md: `./CLAUDE.md` vs `<config_root>/CLAUDE.md`        -> distinct
#   2. Project root IS the config root (`~/.claude` itself tracked as the repo).
#        CLAUDE.md: `./CLAUDE.md` == `<config_root>/CLAUDE.md`        -> COLLIDES
#        rules:     `.claude/rules` resolves to `<config_root>/.claude/rules`,
#                   which is NOT `<config_root>/rules`                -> distinct
#
# So the two comparisons are computed independently rather than from one flag.
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

# --- project scope -----------------------------------------------------------
# Depth 1 by design: CLAUDE.md files nested deeper are subtree memory that loads only
# on demand, and are not this checklist's subject.

if [[ -f "CLAUDE.md" ]]; then
  proj_md_scope=project
  [[ "$md_overlap" -eq 1 ]] && proj_md_scope=both
  emit "$proj_md_scope" claude-md "CLAUDE.md"
fi
[[ -f "CLAUDE.local.md" ]] && emit project claude-local-md "CLAUDE.local.md"

if [[ -d ".claude/rules" ]]; then
  proj_rule_scope=project
  [[ "$rules_overlap" -eq 1 ]] && proj_rule_scope=both
  emit_rules ".claude/rules" "$proj_rule_scope"
fi

# --- user scope --------------------------------------------------------------
# Same resolution as resolve-memory-dir.sh: CLAUDE_CONFIG_DIR relocates the whole
# `~/.claude` tree when set, so the instruction surfaces move with it.

if [[ -n "$config_root" && -d "$config_root" ]]; then
  # Suppressed when it is the same physical file as the project one, already emitted
  # above as `both`.
  if [[ -f "$config_root/CLAUDE.md" && "$md_overlap" -eq 0 ]]; then
    emit user claude-md "$config_root/CLAUDE.md"
  fi

  # Suppressed entirely when the two rules dirs coincide — those files were already
  # emitted above, once, as `both`.
  if [[ -d "$config_root/rules" && "$rules_overlap" -eq 0 ]]; then
    emit_rules "$config_root/rules" user
  fi
fi

exit 0
