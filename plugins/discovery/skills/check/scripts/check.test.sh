#!/usr/bin/env bash
# Tests for check.sh: a healthy plugin passes every row; a PATH without node
# fails the node and hook rows but still reports registration; a hooks.json
# without the hook fails registration.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
CHECK="$HERE/check.sh"
T=$'\t'
fails=0
expect() {
  if [[ "$1" == 0 ]]; then
    echo "PASS: $2"
  else
    echo "FAIL: $2" >&2
    fails=1
  fi
}
has_row() {
  grep -q "^$1${T}$2${T}${3:-}" <<<"$out"
  echo $?
}

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node is not installed"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

out="$(bash "$CHECK")"
expect "$?" "healthy plugin exits 0"
for r in node registration hook; do
  expect "$(has_row "$r" PASS)" "healthy: $r passes"
done

# A PATH holding the tools check.sh uses, but no node.
mkdir -p "$WORK/bin"
for t in bash cat grep dirname printf; do
  p="$(command -v "$t")" && [[ "$p" == /* ]] && ln -sf "$p" "$WORK/bin/$t"
done
out="$(PATH="$WORK/bin" "$WORK/bin/bash" "$CHECK")"
code=$?
expect "$((code != 1))" "no node exits 1"
expect "$(has_row node FAIL)" "no node: node fails"
expect "$(has_row registration PASS)" "no node: registration still reports"
expect "$(has_row hook FAIL 'not run')" "no node: hook not run"

# check.sh reads the plugin it ships in, so each fixture is a plugin copy.
fixture() {
  local dir="$WORK/$1"
  mkdir -p "$dir/hooks" "$dir/skills/check/scripts"
  cp "$PLUGIN/hooks/webfetch-truncation.mjs" "$dir/hooks/"
  cp "$CHECK" "$dir/skills/check/scripts/"
  printf '%s\n' "$2" >"$dir/hooks/hooks.json"
  out="$(bash "$dir/skills/check/scripts/check.sh")"
}

fixture unregistered '{"hooks":{}}'
expect "$(has_row registration FAIL)" "unregistered: registration fails"

# Every string present, but the hook sits under PreToolUse while another
# entry supplies the PostToolUse text: not one PostToolUse entry. A text-only
# check passes this fixture; the structural check must not.
# shellcheck disable=SC2016
fixture split '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"true"}]}],
"PreToolUse":[{"matcher": "WebFetch","hooks":[{"type":"command","command": "node","args":["${CLAUDE_PLUGIN_ROOT}/hooks/webfetch-truncation.mjs"]}]}]}}'
expect "$(has_row registration FAIL)" "split entries: registration fails"

bash "$CHECK" --plugin-root /tmp >/dev/null 2>&1
code=$?
expect "$((code != 2))" "any argument exits 2"

if [[ $fails -eq 0 ]]; then
  echo "check.sh tests passed."
else
  echo "check.sh tests failed." >&2
fi
exit "$fails"
