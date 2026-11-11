#!/usr/bin/env bash
# Fill a secret into a playwright-cli session without the secret reaching output.
#
# Usage: fill-secret.sh <session> <target> <ENV_VAR> [--submit]
#
# Reads the value from the named environment variable, so the secret is never
# on the command line an agent prints. playwright-cli echoes the code it ran,
# fill text included, so its stdout and stderr are discarded; a failure is
# reported by exit status alone.
#
# Exit codes:
#   0  filled
#   2  usage error, or ENV_VAR is unset or empty
#   *  playwright-cli's own non-zero exit status
set -uo pipefail
set +x

usage() {
  printf 'usage: fill-secret.sh <session> <target> <ENV_VAR> [--submit]\n' >&2
  exit 2
}

[[ $# -eq 3 || ($# -eq 4 && "$4" == "--submit") ]] || usage

session="$1"
target="$2"
var_name="$3"
shift 3

[[ -n "$session" && -n "$target" ]] || usage
if [[ ! "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  printf 'fill-secret: %s is not an environment variable name\n' "$var_name" >&2
  exit 2
fi
secret="$(printenv -- "$var_name")"
if [[ -z "$secret" ]]; then
  printf 'fill-secret: %s is unset or empty; set it in your own environment first\n' "$var_name" >&2
  exit 2
fi

playwright-cli -s="$session" fill "$target" "$secret" "$@" >/dev/null 2>&1 || {
  status=$?
  printf 'fill-secret: playwright-cli fill %s failed (exit %d); its output was discarded because it echoes the value. Take a snapshot to see the page state.\n' "$target" "$status" >&2
  exit "$status"
}
printf 'fill-secret: filled %s from %s\n' "$target" "$var_name"
