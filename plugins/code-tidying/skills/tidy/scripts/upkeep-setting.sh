#!/usr/bin/env bash
# Resolve one upkeep setting: the team layer at <home>/code-tidying.yaml, else
# the default. Keys and layers: reference/config.md.
#
# Usage: upkeep-setting.sh upkeep_cadence|upkeep_backstop|upkeep_max_open|upkeep_spec_issue
#
# Prints <value><TAB><source> and exits 0. <source> is `team`, `default`, or
# `default (<why the team value was dropped>)`. upkeep_spec_issue's default is
# empty: the caller refuses to run without it. Exit 2 on a usage error.
#
# The root is the git toplevel of CLAUDE_PROJECT_DIR, else of the current
# directory.
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)"

key="${1:-}"
case "$key" in
upkeep_cadence)
  default=daily
  valid='^(daily|weekly)$'
  ;;
upkeep_backstop)
  default=weekly
  valid='^(weekly|monthly)$'
  ;;
upkeep_max_open)
  default=3
  valid='^[1-9][0-9]{0,3}$'
  ;;
upkeep_spec_issue)
  default=
  valid='^[1-9][0-9]{0,8}$'
  ;;
*)
  echo "upkeep-setting: usage: upkeep-setting.sh upkeep_cadence|upkeep_backstop|upkeep_max_open|upkeep_spec_issue" >&2
  exit 2
  ;;
esac

resolve() {
  printf '%s\t%s\n' "$default" "default${1:+ ($1)}"
  exit 0
}

root="$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --show-toplevel 2>/dev/null)" || resolve

home="$(bash "$LIB/resolve-convention-home.sh" --root "$root" 2>/dev/null)"
case $? in
0) ;;
1 | 4) home=docs/conventions ;;
3) resolve "the convention-home pointer is broken" ;;
*) resolve ;;
esac

rel="$home/code-tidying.yaml"
[[ -f "$root/$rel" ]] || resolve

value="$(bash "$LIB/parse-concern-value.sh" --strict "$root/$rel" "$key" 2>/dev/null)"
(($? == 3)) && resolve "$rel does not parse"
[[ -n "$value" ]] || resolve
[[ "$value" =~ $valid ]] || resolve "$rel $key: ${value:0:40} is not valid"
printf '%s\tteam\n' "$value"
