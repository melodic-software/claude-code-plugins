#!/usr/bin/env bash
# audit-spine.sh — the audit's deterministic spine in one run.
#
# The spine is every check a script can decide: the expanded C1 count, the M1
# index size, the M2 index integrity, the RD1 orphan rules, the N1 nested
# AGENTS.md reachability, and the estimated cost of the always-loaded set. Each
# has its own script; this one runs them in a fixed order and prints one block,
# so the skill's pre-computed header and the report's spine rows come from the
# same invocation and cannot disagree with each other.
#
# OUTPUT: a `Label: value` block (the header), then a `Findings:` block with one
# line per finding in the producing script's own format. `--summary` prints the
# header only. Every line is safe to inject verbatim into the skill body: no
# script here exits non-zero on a finding, and a script that fails to run
# reports `?` for its value rather than aborting the block.
#
# Usage:
#   audit-spine.sh              header + findings
#   audit-spine.sh --summary    header only
#   audit-spine.sh --help

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    if [[ "$(head -1 "$f" | tr -d '\r')" == "---" ]] &&
      tr -d '\r' <"$f" | awk 'NR==1{next} /^---$/{exit} {print}' | grep -q '^paths:'; then
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
