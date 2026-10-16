#!/usr/bin/env bash
# Record the steps a `ready --skip` run skipped in the pull request body: one
# marked block right under `## Verification`, one line per step. A re-run
# replaces the block, never adds a second; no --step removes it. A body with no
# `## Verification` heading gets one appended.
#
# Usage:
#   ready-skip-body.sh --login <login> [--reason <text> --step <step>...]
#       the body on stdin; the new body on stdout
#
# Pass only the steps --skip removed from what would have run, never one
# pre_ready disabled or a built-in condition skipped. The reason is data: it is
# rendered in a code span with backticks, `#`, `<`, `>` and `@` turned into
# spaces, and a closing keyword or "do not merge" broken with a hyphen, so it
# cannot close an issue, mention, hide text or hold the merge.
#
# Exit 0, or 2 for a usage error (stdout empty).
set -uo pipefail

STEPS=(base-merge plan-evidence code-review security-review verify)
START='<!-- ready-skip -->' END='<!-- /ready-skip -->'

die() {
  printf 'ready-skip-body: %s\n' "$1" >&2
  exit 2
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
for step in ${steps[@]+"${steps[@]}"}; do
  [[ " ${STEPS[*]} " == *" $step "* ]] || die "unknown step $(printf '%q' "$step")"
done
if ((${#steps[@]})); then
  ((has_reason)) || die "--step needs --reason"
  reason="${reason//[[:cntrl:]]/ }"
  reason="${reason//[\`#<>@]/ }"
  [[ "$reason" =~ [^[:space:]] ]] || die "--reason is empty"
  shopt -s nocasematch
  re='^(.*[^[:alnum:]_]|)(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]:]+(.*)$'
  while [[ "$reason" =~ $re ]]; do reason="${BASH_REMATCH[1]}${BASH_REMATCH[2]}-${BASH_REMATCH[4]}"; done
  re='^(.*)(do(n[^[:space:]]{0,3}t| not))[[:space:]]+(merge.*)$'
  while [[ "$reason" =~ $re ]]; do reason="${BASH_REMATCH[1]}${BASH_REMATCH[2]}-${BASH_REMATCH[4]}"; done
  shopt -u nocasematch
fi

# Drop an earlier block and the blank line this script put before it.
out=() skipping=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if ((skipping)); then
    [[ "$line" != "$END" ]] || skipping=0
    continue
  fi
  if [[ "$line" == "$START" ]]; then
    skipping=1
    ((${#out[@]})) && [[ -z "${out[${#out[@]} - 1]}" ]] && unset "out[$((${#out[@]} - 1))]"
    continue
  fi
  out+=("$line")
done

block=()
if ((${#steps[@]})); then
  block=("" "$START")
  for step in "${STEPS[@]}"; do
    [[ " ${steps[*]} " == *" $step "* ]] &&
      block+=("- \`$step\` skipped by $login for this run: \`$reason\`")
  done
  block+=("$END")
fi

heading='^##[[:space:]]+Verification[[:space:]]*$'
placed=0
for line in ${out[@]+"${out[@]}"}; do
  printf '%s\n' "$line"
  if ((! placed)) && [[ "$line" =~ $heading ]]; then
    ((${#block[@]})) && printf '%s\n' "${block[@]}"
    placed=1
  fi
done
if ((! placed && ${#block[@]})); then
  ((${#out[@]})) && [[ -n "${out[${#out[@]} - 1]}" ]] && echo
  printf '%s\n' "## Verification" "${block[@]}"
fi
exit 0
