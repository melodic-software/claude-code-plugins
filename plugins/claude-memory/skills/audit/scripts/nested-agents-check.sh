#!/usr/bin/env bash
# nested-agents-check.sh — does every nested AGENTS.md actually load?
#
# Claude Code reads CLAUDE.md, not AGENTS.md (memory doc, "AGENTS.md"): the
# prescribed way to make one load is a CLAUDE.md beside it that imports it
# (`@AGENTS.md`) or a symlink. A subdirectory's CLAUDE.md loads on demand when
# Claude reads files in that directory; an AGENTS.md with no such sibling is
# never loaded at any level of the tree, however well written, and every static
# gate reports green around it. This check is the byte-deterministic set
# difference the audit's judgment tier had to find by hand: nested AGENTS.md
# files minus the ones a sibling CLAUDE.md or CLAUDE.local.md reaches.
#
# Discovery is tracked files only (git ls-files), root-level AGENTS.md excluded
# (that one is the root CLAUDE.md's business, and the audit's C-checks already
# cover the root), and the `.claude`, `node_modules`, `vendor`, and `.git` trees
# skipped so vendored upstream material is never reported as a repo defect. The
# sibling check reads the filesystem, so a gitignored CLAUDE.local.md shim counts.
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
nested-agents-check.sh — flag a tracked nested AGENTS.md no sibling CLAUDE.md imports.

Usage: nested-agents-check.sh [--count|--check|--help]

  (no arg)   print one FAIL line per unwired nested AGENTS.md; exit 0
  --count    print the integer finding count only; exit 0
  --check    print the findings; exit 1 when there is at least one
  --help     this message

Wired = a CLAUDE.md or CLAUDE.local.md in the same directory that is the
AGENTS.md (symlink) or imports it within four hops. Root-level AGENTS.md and the
.claude, node_modules, vendor, and .git trees are not examined.
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
        if (seg[i] == ".claude" || seg[i] == "node_modules" ||
            seg[i] == "vendor" || seg[i] == ".git") next
      }
      print
    }
  ' | LC_ALL=C sort
}

is_wired() {
  local agents="$1" dir want sibling
  dir="$(dirname "$agents")"
  want="$(il_realpath "$agents")"
  for sibling in "$dir/CLAUDE.md" "$dir/CLAUDE.local.md"; do
    [[ -f "$sibling" ]] || continue
    il_reaches "$sibling" "$want" && return 0
  done
  return 1
}

findings=()
while IFS= read -r agents; do
  [[ -n "$agents" ]] || continue
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
  echo "FAIL [N1]: ${agents} is not imported by a sibling CLAUDE.md or CLAUDE.local.md (Claude Code reads CLAUDE.md, not AGENTS.md, so this file never loads); add a one-line \`@AGENTS.md\` CLAUDE.md beside it."
done
[[ "$mode" == "check" ]] && exit 1
exit 0
