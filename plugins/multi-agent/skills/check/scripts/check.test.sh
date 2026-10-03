#!/usr/bin/env bash
# Tests for check.sh: a healthy plugin passes every row; a PATH without node
# fails the node and gate rows but still reports registration; a hooks.json
# without the gate fails registration.
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
for r in node registration gate; do
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
expect "$(has_row gate FAIL 'not run')" "no node: gate not run"

# A plugin root whose hooks.json does not register the gate.
mkdir -p "$WORK/plugin/hooks"
cp "$PLUGIN/hooks/drift-checker-fetch-gate.mjs" "$WORK/plugin/hooks/"
printf '{"hooks":{}}\n' >"$WORK/plugin/hooks/hooks.json"
out="$(bash "$CHECK" --plugin-root "$WORK/plugin")"
expect "$(has_row registration FAIL)" "unregistered: registration fails"

bash "$CHECK" --bogus >/dev/null 2>&1
code=$?
expect "$((code != 2))" "unknown argument exits 2"

if [[ $fails -eq 0 ]]; then
  echo "check.sh tests passed."
else
  echo "check.sh tests failed." >&2
fi
exit "$fails"
