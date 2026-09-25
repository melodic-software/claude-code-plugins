#!/usr/bin/env bash
# memory-index-refs-check.sh — deterministic M2 (auto-memory reference integrity).

set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
memory-index-refs-check.sh — verify MEMORY.md index <-> topic-file integrity.

Usage: memory-index-refs-check.sh [--count|--help]

  (no arg)   print WARN lines: M2-missing (index points at absent file) and
             M2-orphan (topic file not indexed); exit 0
  --count    print integer finding count (missing + orphan); exit 0
  --help     this message

Resolves the current project's memory dir (repo, or the cwd outside one) via the
sibling resolve-memory-dir.sh.
Orphan opt-out: topic file containing `<!-- memory-index-orphan-ignore -->`.
Advisory — always exits 0.
EOF
  exit 0
fi

mode="report"
[[ "${1:-}" == "--count" ]] && mode="count"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# No repo guard here: the sibling resolver handles the non-repo case itself.
memory_dir=$(bash "$SCRIPT_DIR/resolve-memory-dir.sh" 2>/dev/null)
index="$memory_dir/MEMORY.md"

if [[ ! -f "$index" ]]; then
  if [[ "$mode" == "count" ]]; then
    echo "0"
  else
    echo "No MEMORY.md found ($memory_dir) — nothing to check."
  fi
  exit 0
fi

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
