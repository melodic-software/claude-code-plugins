#!/usr/bin/env bash
# rule-scope.sh: what a `.claude/rules/*.md` file declares about how it loads.
# One reader so the audit scripts cannot disagree about which rules are path-scoped.

# Captured before the match, and matched from a here-string rather than a pipe, so neither
# a rule larger than the pipe buffer nor `grep -q` exiting at its first match can turn
# SIGPIPE into the answer under pipefail. `tr -d '\r'` keeps CRLF off anchors.
rule_frontmatter_declares() {
  local file="$1" key="$2" head1 frontmatter
  head1=$(head -1 "$file" | tr -d '\r')
  [[ "$head1" == "---" ]] || return 1
  frontmatter=$(tr -d '\r' <"$file" | awk 'NR==1{next} /^---$/{exit} {print}')
  grep -q "^${key}:" <<<"$frontmatter"
}
