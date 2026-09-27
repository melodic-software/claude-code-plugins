#!/usr/bin/env bash
# audit-spine.sh — the audit's deterministic spine in one run.
# One invocation feeds both the skill's header and the report's spine rows, so they
# cannot disagree. A check that fails to run reports `?` rather than aborting the block.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/rule-scope.sh
source "$SCRIPT_DIR/lib/rule-scope.sh"
# shellcheck source=lib/agents-md.sh
source "$SCRIPT_DIR/lib/agents-md.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
audit-spine.sh — run every deterministic audit check and print one block.

Usage: audit-spine.sh [--summary|--help]

  (no arg)    the `Label: value` header, then a Findings block
  --summary   the header only
  --help      this message
EOF
  exit 0
fi
summary=0
[[ "${1:-}" == "--summary" ]] && summary=1

stat() { bash "$SCRIPT_DIR/$1" "${@:2}" 2>/dev/null || echo "?"; }

rules_total=0
rules_scoped=0
if [[ -d .claude/rules ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    rules_total=$((rules_total + 1))
    if rule_frontmatter_declares "$f" paths; then
      rules_scoped=$((rules_scoped + 1))
    fi
  done < <(find .claude/rules -name '*.md' -type f 2>/dev/null | LC_ALL=C sort)
fi

root_file="none"
for f in CLAUDE.md .claude/CLAUDE.md; do
  [[ -f "$f" ]] && {
    root_file="$f"
    break
  }
done
# Same fallback instruction-load-stats.sh applies, so the header's name and its
# line count are about the same file.
if [[ "$root_file" == "none" ]]; then
  agents_root="$(agents_md_native_files | head -1)"
  [[ -n "$agents_root" ]] && root_file="$agents_root"
fi

echo "Memory files: $(stat memory-dir-stats.sh --md-count)"
echo "MEMORY.md loaded lines (200 cap): $(stat memory-dir-stats.sh --memory-lines)"
echo "MEMORY.md loaded bytes (25KB cap): $(stat memory-dir-stats.sh --memory-bytes)"
echo "Rules files: ${rules_total} (always-loaded: $((rules_total - rules_scoped)), path-scoped: ${rules_scoped})"
echo "Project root file: ${root_file}"
echo "Root file loaded lines, @imports expanded (200 target): $(stat instruction-load-stats.sh --lines)"
echo "CLAUDE.local.md exists: $(test -f CLAUDE.local.md && echo yes || echo no)"
echo "Always-loaded set, estimated tokens (bytes/4): $(stat instruction-load-stats.sh --tokens)"
echo "Nested AGENTS.md unwired (N1): $(stat nested-agents-check.sh --count)"
echo "Orphan always-loaded rules (RD1): $(stat orphan-rule-check.sh --count)"
echo "MEMORY.md index issues (M2): $(stat memory-index-refs-check.sh --count)"

((summary)) && exit 0

echo
echo "Findings:"
findings=0
for script in nested-agents-check.sh orphan-rule-check.sh memory-index-refs-check.sh; do
  while IFS= read -r line; do
    case "$line" in
    FAIL* | WARN*)
      echo "$line"
      findings=$((findings + 1))
      ;;
    *) ;;
    esac
  done < <(bash "$SCRIPT_DIR/$script" 2>/dev/null)
done
((findings == 0)) && echo "none from the deterministic spine"
exit 0
