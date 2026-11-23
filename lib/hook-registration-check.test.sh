#!/usr/bin/env bash
# test-scope: plugins/*/scripts/check-hook-registration.sh
# test-scope: plugins/discovery/hooks/hooks.json plugins/multi-agent/hooks/hooks.json
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
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

shopt -s nullglob
carriers=("$REPO"/plugins/*/scripts/check-hook-registration.sh)
shopt -u nullglob
if ((${#carriers[@]} == 0)); then
  echo "FAIL: no plugin carries scripts/check-hook-registration.sh" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

bin="$(dirname "$(command -v bash)")"
if [[ -e "$bin/node" || -e "$bin/node.exe" ]]; then
  bin="$WORK/bin"
  mkdir -p "$bin"
  for t in bash cat grep dirname printf; do
    p="$(command -v "$t")" && [[ "$p" == /* ]] && ln -sf "$p" "$bin/$t"
  done
fi

for script in "${carriers[@]}"; do
  root="${script%/scripts/check-hook-registration.sh}"
  plugin="${root##*/}"
  fixture() {
    local dir="$WORK/$plugin-$1"
    mkdir -p "$dir/scripts" "$dir/lib"
    cp -R "$root/hooks" "$dir/"
    cp "$script" "$dir/scripts/"
    cp "$HERE/hook-registration-check.sh" "$dir/lib/"
    [[ $# -lt 2 ]] || printf '%s\n' "$2" >"$dir/hooks/hooks.json"
    CHECK="$dir/scripts/check-hook-registration.sh"
  }

  fixture healthy
  out="$(bash "$CHECK")"
  expect "$?" "$plugin healthy: exits 0"
  read -r event matcher _ _ hook < <(grep "^registration${T}PASS${T}" <<<"$out" | cut -f3)
  row="$(tail -n 1 <<<"$out" | cut -f1)"
  for r in node registration "$row"; do
    expect "$(has_row "$r" PASS)" "$plugin healthy: $r passes"
  done
  if [[ -z "${hook:-}" || "$row" == registration ]]; then
    expect 1 "$plugin healthy: rows name the event, matcher, hook and sample row"
    continue
  fi

  out="$(PATH="$bin" "$bin/bash" "$CHECK")"
  code=$?
  expect "$((code != 1))" "$plugin no node: exits 1"
  expect "$(has_row node FAIL)" "$plugin no node: node fails"
  expect "$(has_row registration PASS 'text match only')" "$plugin no node: registration still reports"
  expect "$(has_row "$row" FAIL 'not run')" "$plugin no node: $row not run"

  fixture unregistered '{"hooks":{}}'
  out="$(bash "$CHECK")"
  expect "$(has_row registration FAIL "no $event $matcher hook entry")" "$plugin unregistered: registration fails"

  other=PreToolUse
  [[ "$event" != PreToolUse ]] || other=PostToolUse
  # shellcheck disable=SC2016
  fixture split '{"hooks":{"'"$event"'":[{"matcher":"Bash","hooks":[{"type":"command","command":"true"}]}],
"'"$other"'":[{"matcher": "'"$matcher"'","hooks":[{"type":"command","command": "node","args":["${CLAUDE_PLUGIN_ROOT}/hooks/'"$hook"'"]}]}]}}'
  out="$(bash "$CHECK")"
  expect "$(has_row registration FAIL)" "$plugin split entries (the hook under the other event): registration fails"

  out="$(bash "$CHECK" --plugin-root /tmp 2>&1)"
  code=$?
  expect "$((code != 2))" "$plugin: any argument exits 2"
done

if [[ $fails -eq 0 ]]; then
  echo "hook-registration-check.sh tests passed."
else
  echo "hook-registration-check.sh tests failed." >&2
fi
exit "$fails"
