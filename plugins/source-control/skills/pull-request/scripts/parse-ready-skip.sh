#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=pre-ready-steps.sh
source "$(dirname "${BASH_SOURCE[0]}")/pre-ready-steps.sh"

die() {
  printf 'parse-ready-skip: %s\n' "$2" >&2
  exit "$1"
}

unattended=0 skip="" reason="" has_skip=0 has_reason=0
while (($#)); do
  case "$1" in
  --unattended) unattended=1 ;;
  --skip | --reason)
    (($# >= 2)) || die 2 "$1 needs a value"
    if [[ "$1" == --skip ]]; then
      ((! has_skip)) || die 2 "--skip is given twice"
      skip="$2" has_skip=1
    else
      ((! has_reason)) || die 2 "--reason is given twice"
      reason="$2" has_reason=1
    fi
    shift
    ;;
  *) die 2 "unexpected argument $(printf '%q' "$1")" ;;
  esac
  shift
done

((has_skip)) || {
  ((! has_reason)) || die 2 "--reason needs --skip"
  exit 0
}
((! unattended)) || die 3 "--skip needs a person present; an unattended run runs every step"
((has_reason)) || die 2 "--skip needs --reason"
reason="${reason//[[:cntrl:]]/ }"
[[ "$reason" =~ [^[:space:]] ]] || die 2 "--reason is empty"

[[ "$skip" != *[[:cntrl:]]* ]] || die 2 "--skip holds a control character"
given=" "
IFS=, read -r -a items <<<"$skip,"
((${#items[@]})) || die 2 "--skip names no step"
for item in "${items[@]}"; do
  [[ -n "$item" ]] || die 2 "--skip has an empty step name"
  [[ " ${PRE_READY_STEPS[*]} " == *" $item "* ]] || die 2 "unknown step $(printf '%q' "$item"); the steps are ${PRE_READY_STEPS[*]}"
  [[ "$given" != *" $item "* ]] || die 2 "step $item is given twice"
  given+="$item "
done

printf 'reason\t%s\n' "$reason"
for step in "${PRE_READY_STEPS[@]}"; do
  [[ "$given" != *" $step "* ]] || printf 'skip\t%s\n' "$step"
done
