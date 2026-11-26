#!/usr/bin/env bash
# Custom shell syntax: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#custom-shell
set -u

if [[ $# -ne 2 || ! "$1" =~ ^[A-Za-z0-9._-]+$ || -z "$2" ]]; then
  echo "usage: $0 <check-name> <script-file>  (check-name: letters, digits, '.', '_', '-')" >&2
  exit 2
fi

check=$1
script=$2
dir=${HYGIENE_OUTPUT_DIR:-${RUNNER_TEMP:+$RUNNER_TEMP/hygiene}}
log=$dir/$check.log

if [[ -z "$dir" ]] || ! mkdir -p "$dir" 2>/dev/null || ! : >"$log" 2>/dev/null; then
  echo "::warning title=$check output not captured::Could not write $log; the aggregator will report this gate without its output."
  exec bash -e "$script"
fi

bash -e "$script" 2>&1 | tee "$log"
exit "${PIPESTATUS[0]}"
