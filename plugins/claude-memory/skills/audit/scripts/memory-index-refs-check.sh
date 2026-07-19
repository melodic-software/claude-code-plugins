#!/usr/bin/env bash
# memory-index-refs-check.sh — deterministic M2 (auto-memory reference integrity).
#
# Two directions, both deterministic (no LLM judgment):
#   FORWARD (missing): a MEMORY.md index link `](topic.md)` whose target file is absent.
#   REVERSE (orphan):  a `*.md` topic file present in the memory dir but NOT linked from
#                      MEMORY.md. The standard M2 only catches the forward direction; the
#                      orphan direction (a topic file that fell out of the index) is the
#                      reverse-drift gap this adds.
#
# Resolves the CURRENT repo's memory dir via the sibling resolver (NOT a cross-project
# glob). Orphan opt-out: a topic file containing `<!-- memory-index-orphan-ignore -->`
# (e.g. an intentional staging file not yet indexed) is skipped.
#
# WARN-tier / advisory: prints findings, ALWAYS exits 0. Consumed by the audit
# skill (check M2).
#
# Usage:
#   memory-index-refs-check.sh           # human-readable findings
#   memory-index-refs-check.sh --count   # integer finding count (missing + orphan)
#   memory-index-refs-check.sh --help

set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
memory-index-refs-check.sh — verify MEMORY.md index <-> topic-file integrity.

Usage: memory-index-refs-check.sh [--count|--help]

  (no arg)   print WARN lines: M2-missing (index points at absent file) and
             M2-orphan (topic file not indexed); exit 0
  --count    print integer finding count (missing + orphan); exit 0
  --help     this message

Resolves the current repo's memory dir via the sibling resolve-memory-dir.sh.
Orphan opt-out: topic file containing `<!-- memory-index-orphan-ignore -->`.
Advisory — always exits 0.
EOF
  exit 0
fi

mode="report"
[[ "${1:-}" == "--count" ]] && mode="count"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
if [[ -z "$repo_root" ]]; then
  echo "memory-index-refs-check: not inside a git repository" >&2
  exit 1
fi

memory_dir=$(bash "$SCRIPT_DIR/resolve-memory-dir.sh" 2>/dev/null)
index="$memory_dir/MEMORY.md"

# Fresh repo / no memory yet: nothing to check.
if [[ ! -f "$index" ]]; then
  [[ "$mode" == "count" ]] && echo "0" || echo "No MEMORY.md found ($memory_dir) — nothing to check."
  exit 0
fi

# Build the set of markdown link targets ending in .md from MEMORY.md.
declare -A linked=()
while IFS= read -r target; do
  [[ -n "$target" ]] && linked["$target"]=1
done < <(grep -oE '\]\([^)]+\.md\)' "$index" | sed 's/](//; s/)//' | tr -d '\r')

missing=()
for target in "${!linked[@]}"; do
  [[ -f "$memory_dir/$target" ]] || missing+=("$target")
done

orphan=()
shopt -s nullglob
for file in "$memory_dir"/*.md; do
  base=$(basename "$file")
  [[ "$base" == "MEMORY.md" ]] && continue
  [[ -n "${linked[$base]:-}" ]] && continue
  grep -q '<!-- memory-index-orphan-ignore -->' "$file" && continue
  orphan+=("$base")
done
shopt -u nullglob

if [[ "$mode" == "count" ]]; then
  printf '%s\n' "$((${#missing[@]} + ${#orphan[@]}))"
  exit 0
fi

if [[ "${#missing[@]}" -eq 0 && "${#orphan[@]}" -eq 0 ]]; then
  echo "MEMORY.md index integrity OK (all links resolve, no orphan topic files)."
  exit 0
fi

for target in "${missing[@]}"; do
  echo "WARN [M2-missing]: MEMORY.md links ${target} but the file does not exist."
done
for base in "${orphan[@]}"; do
  echo "WARN [M2-orphan]: ${base} exists in the memory dir but is not indexed in MEMORY.md (add an index line, or mark the file with <!-- memory-index-orphan-ignore -->)."
done
exit 0
