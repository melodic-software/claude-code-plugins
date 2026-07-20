#!/usr/bin/env bash
# orphan-rule-check.sh — reverse-drift detector for the always-loaded rule layer.
#
# Flags `.claude/rules/*.md` files that are ALWAYS-LOADED (no `paths:` frontmatter,
# so they cost context every session) yet are referenced by NO tracked file. The
# standard audit checks memory->codebase (does a referenced file still
# exist?); this checks the reverse codebase->memory direction: a new always-loaded
# rule that nothing indexes is pure per-session token tax until someone trips over it.
#
# Path-scoped rules (`paths:` frontmatter) are EXEMPT — they load only on matching-file
# Read, so being unreferenced costs nothing per session.
#
# Reference search is tracked-files-only (git grep), excluding the in-repo memory tier
# (the topic-docs seam `memory_dir`, default `.work/`) and the rule's own file. Reading
# the seam rather than hardcoding the default keeps a consumer's overridden memory tier —
# ephemeral task artifacts — out of the search so it cannot register false references.
# Gitignored files (e.g. CLAUDE.local.md) are excluded automatically — a per-user
# override file is not a shared reference.
#
# WARN-tier / advisory: prints findings, ALWAYS exits 0. Consumed by the audit
# skill (check RD1).
#
# Usage:
#   orphan-rule-check.sh           # human-readable findings, one orphan per line
#   orphan-rule-check.sh --count   # integer orphan count only
#   orphan-rule-check.sh --help

set -uo pipefail

# Absolute path to this script's dir, resolved before any `cd` so the sibling
# shared parser stays locatable regardless of how we were invoked.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
orphan-rule-check.sh — flag always-loaded .claude/rules/*.md referenced by no tracked file.

Usage: orphan-rule-check.sh [--count|--help]

  (no arg)   print one WARN line per orphan rule; exit 0
  --count    print the integer orphan count only; exit 0
  --help     this message

Always-loaded = no `paths:` frontmatter. Path-scoped rules are exempt. Reference
search is git-grep over tracked files, excluding the in-repo memory tier (topic-docs
`memory_dir`, default `.work/`) and the rule's own file. Advisory — always exits 0.
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

# Resolve the in-repo memory tier from the topic-docs seam (`.claude/topic-docs.yaml`
# `memory_dir`) via the shared parser (quote-aware, comment-safe) and exclude THAT
# path from the reference search. NOTE: this is the tracked in-repo tier, distinct
# from the auto-memory dir the sibling resolve-memory-dir.sh derives. As a
# non-interactive detector it degrades straight to the documented `.work` default
# when the seam is unset; the contract's inferred/interactive rungs (a save-point
# convention declared in CLAUDE.md / .claude/rules) are the calling skill's job.
seam=$("$SCRIPT_DIR/parse-concern-value.sh" "${repo_root}/.claude/topic-docs.yaml" memory_dir)
memory_dir="${seam:-.work}"

# A rule is always-loaded unless its frontmatter declares `paths:`. Frontmatter is the
# leading `---` ... `---` block.
is_always_loaded() {
  local file="$1" head1 fm
  # tr -d '\r' for parity with sibling scripts — a CRLF checkout would otherwise leave
  # `---\r` / `paths:\r`, defeating the anchored greps and misclassifying scoped rules.
  head1=$(head -1 "$file" | tr -d '\r')
  [[ "$head1" == "---" ]] || return 0 # no frontmatter at all => always-loaded
  fm=$(tr -d '\r' <"$file" | awk 'NR==1{next} /^---$/{exit} {print}')
  printf '%s' "$fm" | grep -q '^paths:' && return 1 # has paths: => path-scoped
  return 0
}

orphans=()
shopt -s nullglob
for file in .claude/rules/*.md; do
  is_always_loaded "$file" || continue
  base=$(basename "$file")
  # Any tracked file (outside the memory tier, excluding the rule itself) referencing
  # the basename. -xF: fixed-string whole-line match, so path dots stay literal.
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
    echo "WARN [RD1]: .claude/rules/${base} is always-loaded but referenced by no tracked file (orphan — per-session token tax or candidate for path-scoping / removal)."
  done
fi
exit 0
