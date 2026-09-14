#!/usr/bin/env bash
# rule-scope.sh: what a `.claude/rules/*.md` file declares about how it loads.
#
# Sourced by the audit scripts that split the rules layer into an always-loaded
# half and a path-scoped one: audit-spine.sh (the header's rules counts),
# instruction-load-stats.sh (which rules join the always-loaded set) and
# orphan-rule-check.sh (which rules are eligible for the RD1 finding). One
# reader so the three answers cannot disagree.
#
# The reading follows the memory doc: a rule whose frontmatter declares `paths:`
# loads only when a matching file is read, while every other rule, including one
# with no frontmatter at all, is in context every session.
#
# Functions (pure, none writes anything):
#   rule_frontmatter_declares <file> <key>   0 when the frontmatter declares <key>:

# Frontmatter is the leading `---` ... `---` block. It is captured before the
# match rather than piped into it, so that a rule larger than the pipe buffer
# cannot turn the producer's SIGPIPE into the answer under `set -o pipefail`.
# `tr -d '\r'` keeps a CRLF checkout from leaving `---\r` / `paths:\r`, which
# would defeat the anchored matches and misclassify a scoped rule.
rule_frontmatter_declares() {
  local file="$1" key="$2" head1 frontmatter
  head1=$(head -1 "$file" | tr -d '\r')
  [[ "$head1" == "---" ]] || return 1
  frontmatter=$(tr -d '\r' <"$file" | awk 'NR==1{next} /^---$/{exit} {print}')
  printf '%s' "$frontmatter" | grep -q "^${key}:"
}
