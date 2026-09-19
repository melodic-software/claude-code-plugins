#!/usr/bin/env bash
# nested-agents-check.sh — does every nested AGENTS.md actually load?
#
# A nested CLAUDE.md and a nested AGENTS.md share one trigger: Claude reads a
# file in that directory with the Read tool. What separates them is that a
# CLAUDE.md in that directory or any directory above it stops Claude Code
# reading AGENTS.md at all, and then only an import (`@AGENTS.md`) or a symlink
# from one of those CLAUDE.md files carries the AGENTS.md into context.
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
# So this check flags the case that is a defect either way: a nested AGENTS.md
# that a CLAUDE.md on its own path blocks and that no CLAUDE.md or
# CLAUDE.local.md reaches. A nested AGENTS.md with nothing blocking it is not a
# finding, because the shim would add nothing the loader is not already doing.
#
# Discovery is tracked files only (git ls-files), root-level AGENTS.md excluded
# (that one is the root CLAUDE.md's business, and the audit's C-checks already
# cover the root), and the `.claude`, `.codex`, `.cursor`, `.github`,
# `node_modules`, `vendor`, and `.git` trees skipped, so neither vendored
# upstream material nor another tool's own instruction files are reported as a
# repo defect. The sibling check reads the filesystem, so a gitignored
# CLAUDE.local.md shim counts.
# Reachability uses lib/imports.sh, the same parser instruction-load-stats.sh
# counts with: import chase to four hops, symlinks resolved.
#
# Advisory by default: prints findings, exits 0. `--check` exits 1 when any
# finding exists, for a CI gate. Consumed by the audit skill (check N1).
#
# Usage:
#   nested-agents-check.sh            # one finding per unwired nested AGENTS.md; exit 0
#   nested-agents-check.sh --count    # integer finding count only; exit 0
#   nested-agents-check.sh --check    # findings; exit 1 when there is at least one
#   nested-agents-check.sh --help

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

Blocked = a CLAUDE.md or CLAUDE.local.md in its own directory or any directory
above it, or the root .claude/CLAUDE.md; Claude Code reads those instead of the
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

# Wired = some instruction entry point reaches the file. The sibling CLAUDE.md
# or CLAUDE.local.md is the prescribed layout, and it is checked first. A
# CLAUDE.md or CLAUDE.local.md in any ancestor directory, or the root's
# .claude/CLAUDE.md, is also an entry point: the root ones load at launch and
# an ancestor's loads when Claude reads under it, and an import from either
# brings the nested AGENTS.md in with it. A file reached that way loads, so it
# is not a finding, whatever layout it uses.
is_wired() {
  local agents="$1" dir want entry
  dir="$(dirname "$agents")"
  want="$(il_realpath "$agents")"
  while :; do
    for entry in "$dir/CLAUDE.md" "$dir/CLAUDE.local.md"; do
      [[ -f "$entry" ]] || continue
      il_reaches "$entry" "$want" && return 0
    done
    [[ "$dir" == "." ]] && break
    dir="$(dirname "$dir")"
  done
  [[ -f ".claude/CLAUDE.md" ]] && il_reaches ".claude/CLAUDE.md" "$want"
}

# Blocked = a CLAUDE.md, CLAUDE.local.md or root .claude/CLAUDE.md sits on the
# file's own path, which is what stops Claude Code reading the AGENTS.md beside
# it. Only a blocked file needs the import; an unblocked one is read directly
# wherever AGENTS.md support is available. Nothing here can see a CLAUDE.md
# above the repository root, so that case is the operator's to know.
is_blocked() {
  local agents="$1" dir
  dir="$(dirname "$agents")"
  while :; do
    [[ -f "$dir/CLAUDE.md" || -f "$dir/CLAUDE.local.md" ]] && return 0
    [[ "$dir" == "." ]] && break
    dir="$(dirname "$dir")"
  done
  [[ -f ".claude/CLAUDE.md" ]]
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
