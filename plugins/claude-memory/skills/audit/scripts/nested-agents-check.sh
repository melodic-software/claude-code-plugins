#!/usr/bin/env bash
# nested-agents-check.sh — does every nested AGENTS.md actually load?
#
#   Claim: Claude Code attaches a subdirectory's AGENTS.md when Claude opens a
#     file there with the Read tool and neither that directory nor any directory
#     above it carries a CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md;
#     otherwise it reads the CLAUDE.md files instead.
#   Basis: code.claude.com/docs/en/memory, "AGENTS.md" and "When Claude Code
#     reads AGENTS.md"; confirmed by canary runs on Claude Code 2.1.278.
#   As of: 2026-09-19.
#   Recheck trigger: that section changes which file names count for the check,
#     or a release note names AGENTS.md or instruction-file loading.
#
# AGENTS.md discovery is tracked files only, but the blocking and wiring checks
# read the filesystem, so a gitignored CLAUDE.local.md shim counts.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/imports.sh
source "$SCRIPT_DIR/lib/imports.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
nested-agents-check.sh — flag a tracked nested AGENTS.md that a CLAUDE.md blocks
and no CLAUDE.md imports.

Usage: nested-agents-check.sh [--count|--check|--help]

  (no arg)   print one FAIL line per unwired nested AGENTS.md; exit 0
  --count    print the integer finding count only; exit 0
  --check    print the findings; exit 1 when there is at least one
  --help     this message

Blocked = a CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md in its own
directory or any directory above it; Claude Code reads those instead of the
AGENTS.md. Wired = one of them is the AGENTS.md (symlink) or imports it within
four hops. A nested AGENTS.md nothing blocks is read directly and is not a
finding. Root-level AGENTS.md and the .claude, .codex, .cursor, .github,
node_modules, vendor, and .git trees are not examined.
EOF
  exit 0
fi

mode="report"
case "${1:-}" in
"") ;;
--count) mode="count" ;;
--check) mode="check" ;;
*)
  echo "nested-agents-check: unknown argument: $1" >&2
  exit 2
  ;;
esac

repo_root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
if [[ -z "$repo_root" ]]; then
  echo "nested-agents-check: not inside a git repository" >&2
  exit 1
fi
cd "$repo_root" || exit 1

nested_agents() {
  git ls-files -z 2>/dev/null | tr '\0' '\n' | awk '
    $0 == "" { next }
    {
      n = split($0, seg, "/")
      if (n < 2) next
      if (seg[n] != "AGENTS.md") next
      for (i = 1; i < n; i++) {
        if (seg[i] == ".claude" || seg[i] == ".codex" || seg[i] == ".cursor" ||
            seg[i] == ".github" || seg[i] == "node_modules" ||
            seg[i] == "vendor" || seg[i] == ".git") next
      }
      print
    }
  ' | LC_ALL=C sort
}

# Wired = any of the three names in its own or any ancestor directory reaches the
# file, since each of those loads and carries its imports in.
#
# All three names count at EVERY level, the root's `.claude/CLAUDE.md` included
# but not alone: the memory page counts "a CLAUDE.md, .claude/CLAUDE.md, or
# CLAUDE.local.md in your working directory or any directory above it", and
# fires the nested attach only where a subdirectory "has none of the three
# CLAUDE.md files of its own" (code.claude.com/docs/en/memory, "When Claude
# Code reads AGENTS.md"; fetched 2026-09-19; recheck when that list changes).
is_wired() {
  local agents="$1" dir want entry
  dir="$(dirname "$agents")"
  want="$(il_realpath "$agents")"
  while :; do
    for entry in "$dir/CLAUDE.md" "$dir/.claude/CLAUDE.md" "$dir/CLAUDE.local.md"; do
      [[ -f "$entry" ]] || continue
      il_reaches "$entry" "$want" && return 0
    done
    [[ "$dir" == "." ]] && break
    dir="$(dirname "$dir")"
  done
  return 1
}

# Blocked = one of the three names sits on the file's own path. A CLAUDE.md
# above the repository root is invisible here; that case is the operator's to know.
is_blocked() {
  local agents="$1" dir
  dir="$(dirname "$agents")"
  while :; do
    [[ -f "$dir/CLAUDE.md" || -f "$dir/.claude/CLAUDE.md" || -f "$dir/CLAUDE.local.md" ]] && return 0
    [[ "$dir" == "." ]] && break
    dir="$(dirname "$dir")"
  done
  return 1
}

findings=()
while IFS= read -r agents; do
  [[ -n "$agents" ]] || continue
  is_blocked "$agents" || continue
  is_wired "$agents" || findings+=("$agents")
done < <(nested_agents)

if [[ "$mode" == "count" ]]; then
  printf '%s\n' "${#findings[@]}"
  exit 0
fi

if [[ "${#findings[@]}" -eq 0 ]]; then
  echo "No unwired nested AGENTS.md files."
  exit 0
fi
for agents in "${findings[@]}"; do
  echo "FAIL [N1]: ${agents} is blocked by a CLAUDE.md on its own path and no CLAUDE.md or CLAUDE.local.md imports it, so this file never loads; add a one-line \`@AGENTS.md\` CLAUDE.md beside it."
done
[[ "$mode" == "check" ]] && exit 1
exit 0
