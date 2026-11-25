#!/usr/bin/env bash

rule_frontmatter_declares() {
  local file="$1" key="$2" head1 frontmatter
  head1=$(head -1 "$file" | tr -d '\r')
  [[ "$head1" == "---" ]] || return 1
  frontmatter=$(tr -d '\r' <"$file" | awk 'NR==1{next} /^---$/{exit} {print}')
  grep -q "^${key}:" <<<"$frontmatter"
}
