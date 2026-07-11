#!/usr/bin/env bash
# Partial extract-ssot verify facts. No PROCEED/REFUSE verdict.
#
# Output: Phrase, Instance/Citation/Primary URL counts and samples, scoped to
# the tracked *.md files of the repository the script runs in.
# Exit: 0 for fact runs (fact-emitter must never fail the caller; -e and
# pipefail omitted so partial grep failures don't abort the run); 2 on
# argument errors.
set -u

PHRASE=""
MAX_SAMPLES=20

usage() {
  cat <<'EOF'
emit-verify-facts.sh — Tier-0 facts for /extract-ssot verify gates 1–3.

Usage:
  emit-verify-facts.sh --phrase "<discriminating phrase>"
  emit-verify-facts.sh --help

Emits instance, citation-pattern, and primary-URL hit counts across the
consuming repository's tracked markdown. Verdict stays in the skill.
Exit: 0 (fact runs) / 2 (argument errors).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --phrase)
    PHRASE="${2:-}"
    shift
    [[ $# -gt 0 ]] && shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "emit-verify-facts.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  esac
done

if [[ -z "$PHRASE" ]]; then
  echo "emit-verify-facts.sh: --phrase is required" >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
if [[ -n "$repo_root" ]]; then
  cd "$repo_root" 2>/dev/null || true
fi

# git pathspec '*.md' matches tracked markdown at any depth.
SCOPE='*.md'

# Count grep hits piped on stdin, echoing the first MAX_SAMPLES with a per-hit
# label and a trailing count line. Empty lines (no matches) don't count.
emit_facts() {
  local sample_label="$1" count_label="$2"
  local count=0 hit
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    count=$((count + 1))
    [[ $count -le $MAX_SAMPLES ]] && printf '%s: %s\n' "$sample_label" "$hit"
  done
  printf '%s: %s\n' "$count_label" "$count"
}

printf 'Phrase: %s\n' "$PHRASE"
printf 'Scope: tracked %s files\n' "$SCOPE"

citation_regex='per [a-z0-9./_-]+\.md'
url_regex='(code|platform)\.(claude|anthropic)\.com|tools\.ietf\.org/rfc|learn\.microsoft\.com'

git grep -nF "$PHRASE" -- "$SCOPE" 2>/dev/null | tr -d '\r' |
  emit_facts 'Instance' 'Instance hit count'
git grep -nE "$citation_regex" -- "$SCOPE" 2>/dev/null | tr -d '\r' |
  emit_facts 'Citation sample' 'Citation pattern hit count'
git grep -nE "$url_regex" -- "$SCOPE" 2>/dev/null | tr -d '\r' |
  emit_facts 'Primary URL sample' 'Primary URL hit count'

exit 0
