#!/usr/bin/env bash
# rule-scope.sh: what a `.claude/rules/*.md` file declares about how it loads.
# One reader so the audit scripts cannot disagree about which rules are path-scoped.

# Captured before the match, not piped into it, so a rule larger than the pipe buffer
# cannot turn SIGPIPE into the answer under pipefail. `tr -d '\r'` keeps CRLF off anchors.
rule_frontmatter_declares() {
  local file="$1" key="$2" head1 frontmatter
  head1=$(head -1 "$file" | tr -d '\r')
  [[ "$head1" == "---" ]] || return 1
  frontmatter=$(tr -d '\r' <"$file" | awk 'NR==1{next} /^---$/{exit} {print}')
  printf '%s' "$frontmatter" | grep -q "^${key}:"
}
