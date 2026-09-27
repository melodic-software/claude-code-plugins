#!/usr/bin/env bash
# orphan-rule-check.sh — reverse-drift detector for the always-loaded rule layer.
# A rule with `description:` is never an orphan: the rendered rules index omits
# unscoped rules, so being unreferenced alone does not mean nobody can find it.

set -uo pipefail

# Resolved before the `cd` below so the sibling scripts stay locatable.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/rule-scope.sh
source "$SCRIPT_DIR/lib/rule-scope.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
orphan-rule-check.sh — flag always-loaded .claude/rules/*.md that nothing names or describes.

Usage: orphan-rule-check.sh [--count|--help]

  (no arg)   print one WARN line per orphan rule; exit 0
  --count    print the integer orphan count only; exit 0
  --help     this message

Orphan = no `paths:` frontmatter (always-loaded), no `description:` frontmatter,
and no tracked file referencing it. A rule that describes itself is not an orphan;
path-scoped rules are exempt. Reference search is git-grep over tracked files,
excluding the in-repo memory tier (topic-docs `memory_dir`, default `.work/`) and
the rule's own file. Each finding names the file's provenance (local or synced).
Advisory — always exits 0.
EOF
  exit 0
fi

mode="report"
[[ "${1:-}" == "--count" ]] && mode="count"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
if [[ -z "$repo_root" ]]; then
  echo "orphan-rule-check: not inside a git repository" >&2
  exit 1
fi
cd "$repo_root" || exit 1

# The in-repo memory tier, not the auto-memory dir resolve-memory-dir.sh derives.
# Unset falls straight to `.work`; the inferred and interactive rungs are the skill's job.
seam=$("$SCRIPT_DIR/parse-concern-value.sh" "${repo_root}/.claude/topic-docs.yaml" memory_dir)
memory_dir="${seam:-.work}"

is_always_loaded() {
  ! rule_frontmatter_declares "$1" paths
}

has_description() {
  rule_frontmatter_declares "$1" description
}

orphans=()
shopt -s nullglob
for file in .claude/rules/*.md; do
  is_always_loaded "$file" || continue
  has_description "$file" && continue
  base=$(basename "$file")
  # -xF: fixed-string whole-line match, so path dots stay literal.
  local_refs=$(git grep -l -F -- "$base" -- ":(exclude)${memory_dir}/" 2>/dev/null | grep -vcxF -- "$file" || true)
  [[ "$local_refs" -eq 0 ]] && orphans+=("$base")
done
shopt -u nullglob

if [[ "$mode" == "count" ]]; then
  printf '%s\n' "${#orphans[@]}"
  exit 0
fi

if [[ "${#orphans[@]}" -eq 0 ]]; then
  echo "No orphan always-loaded rules."
else
  for base in "${orphans[@]}"; do
    file=".claude/rules/${base}"
    IFS=$'\t' read -r owner signal upstream < <(bash "$SCRIPT_DIR/file-provenance.sh" "$file")
    if [[ "$owner" == "synced" ]]; then
      route="synced (${signal}, upstream: ${upstream}): fix at the sync's source, not here; a downstream edit is overwritten by the next sync"
    else
      route="local: add a description: line, a paths: scope, a reference from an always-loaded surface, or remove it"
    fi
    echo "WARN [RD1]: ${file} is always-loaded, has no description: frontmatter, and is referenced by no tracked file (orphan, per-session token tax; ${route})."
  done
fi
exit 0
