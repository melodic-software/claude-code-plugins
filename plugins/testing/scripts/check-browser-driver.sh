#!/usr/bin/env bash
# check-browser-driver.sh — stop a /testing:run-e2e playwright drive whose
# browser tool is not installed.
#
# Resolves browser_driver through `resolve-config.sh e2e` and checks that the
# command it names is an executable file on PATH. It takes the arguments
# resolve-config.sh e2e takes (--root, --home, --user browser_driver=<value>).
#
# Exit: 0 the command resolves, 1 it does not (the message on stderr names the
# setting, the value, its source and the two ways forward), 2 the setting did
# not resolve (resolve-config.sh's own exit and message).
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.

resolved="$(bash "$here/resolve-config.sh" e2e "$@")" || exit 2

tool="" source=""
while IFS=$'\t' read -r key val src; do
  [[ "$key" == browser_driver ]] || continue
  tool="$val" source="$src"
done <<<"$resolved"
if [[ -z "$tool" ]]; then
  printf 'check-browser-driver: browser_driver did not resolve\n' >&2
  exit 2
fi

if type -P -- "$tool" >/dev/null 2>&1; then
  printf 'browser_driver: %s resolves on PATH (source: %s)\n' "$tool" "$source"
  exit 0
fi

cat >&2 <<EOF
check-browser-driver: browser_driver is '$tool' (source: $source), and no command named '$tool' is on PATH. The run stops before driving anything.
Ways forward: install '$tool', or set browser_driver to a browser tool you have, in .claude/testing.local.yaml, docs/conventions/testing.yaml, ~/.claude/testing.yaml or the testing plugin's browser_driver option.
No other browser tool is used as a silent substitute, and a run never switches tools partway through.
EOF
exit 1
