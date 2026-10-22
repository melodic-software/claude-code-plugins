#!/usr/bin/env bash
# Build the PR conversation comment that records a `ready --skip` run: one line
# per skipped step, in run order. Comments are append-only, so the record never
# rewrites the body or a hold in it.
#
# Usage:
#   ready-skip-comment.sh --login <login> --reason <text> --step <step>...
#
# Pass only the steps --skip removed from what would have run, never one
# pre_ready disabled or a built-in condition skipped. The reason is data: it is
# rendered in a code span with backticks, `#`, `<`, `>`, `@` and control
# characters turned into spaces, and a closing keyword or the do-not-merge
# phrase broken with a hyphen, so it cannot link or close an issue, mention,
# hide text or read as a hold.
#
# Exit 0, or 2 for a usage error (stdout empty).
set -uo pipefail

# shellcheck source=pre-ready-steps.sh
source "$(dirname "${BASH_SOURCE[0]}")/pre-ready-steps.sh"

die() {
  printf 'ready-skip-comment: %s\n' "$1" >&2
  exit 2
}

# The reason as inert text for a rendered comment.
neutralize() {
  local s="$1" re
  s="${s//[[:cntrl:]]/ }"
  s="${s//[\`#<>@]/ }"
  shopt -s nocasematch
  re='^(.*[^[:alnum:]_]|)(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]:]+(.*)$'
  while [[ "$s" =~ $re ]]; do s="${BASH_REMATCH[1]}${BASH_REMATCH[2]}-${BASH_REMATCH[4]}"; done
  re='^(.*)(do(n[^[:space:]]{0,3}t|[[:space:]]+not))[[:space:]]+(merge.*)$'
  while [[ "$s" =~ $re ]]; do s="${BASH_REMATCH[1]}${BASH_REMATCH[2]}-${BASH_REMATCH[4]}"; done
  shopt -u nocasematch
  printf '%s' "$s"
}

login="" reason="" has_reason=0 steps=()
while (($#)); do
  case "$1" in
  --login | --reason | --step)
    (($# >= 2)) || die "$1 needs a value"
    if [[ "$1" == --login ]]; then
      login="$2"
    elif [[ "$1" == --reason ]]; then
      reason="$2" has_reason=1
    else
      steps+=("$2")
    fi
    shift
    ;;
  *) die "unexpected argument $(printf '%q' "$1")" ;;
  esac
  shift
done

[[ "$login" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || die "--login needs a GitHub login"
((${#steps[@]})) || die "--step names no step: there is nothing to record"
for step in "${steps[@]}"; do
  [[ " ${PRE_READY_STEPS[*]} " == *" $step "* ]] || die "unknown step $(printf '%q' "$step")"
done
((has_reason)) || die "--step needs --reason"
reason="$(neutralize "$reason")"
[[ "$reason" =~ [^[:space:]] ]] || die "--reason is empty"

for step in "${PRE_READY_STEPS[@]}"; do
  # The backticks are markdown code spans, not command substitution.
  # shellcheck disable=SC2016
  [[ " ${steps[*]} " != *" $step "* ]] || printf -- '- `%s` skipped by %s for this run: `%s`\n' "$step" "$login" "$reason"
done
