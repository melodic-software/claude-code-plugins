#!/usr/bin/env bash
# Every plugins/*/hooks/probe-prerequisite.sh must agree with its plugin's
# prerequisites.json: the probe hardcodes no tool name or install text, reports
# each declared tool (name, check, install) when it is missing, stays silent
# when it is present, and installs nothing.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0
CASES=0
pass() { CASES=$((CASES + 1)); printf 'PASS: %s\n' "$1"; }
fail() { CASES=$((CASES + 1)); FAILED=$((FAILED + 1)); printf 'FAIL: %s\n' "$1" >&2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A PATH holding the system tools but none of the declared binaries.
mapfile -t DECLARED < <(jq -r '.tools[].name' "$REPO"/plugins/*/prerequisites.json | sort -u)
declare -A IS_DECLARED=()
for name in "${DECLARED[@]}"; do IS_DECLARED[$name]=1; done
mkdir -p "$WORK/sysbin" "$WORK/stubs" "$WORK/cwd"
for dir in /usr/local/bin /usr/bin /bin; do
  for exe in "$dir"/*; do
    base="${exe##*/}"
    [[ -x "$exe" && ! -e "$WORK/sysbin/$base" ]] || continue
    [[ -n "${IS_DECLARED[$base]:-}" ]] && continue
    ln -s "$exe" "$WORK/sysbin/$base"
  done
done
for name in "${DECLARED[@]}"; do
  printf '#!/bin/sh\nexit 0\n' >"$WORK/stubs/$name"
  chmod +x "$WORK/stubs/$name"
done

probes=("$REPO"/plugins/*/hooks/probe-prerequisite.sh)
[[ -e "${probes[0]}" ]] || { echo "no probes found" >&2; exit 1; }
first="${probes[0]}"

for probe in "${probes[@]}"; do
  root="${probe%/hooks/*}"
  plugin="${root##*/}"
  manifest="$root/prerequisites.json"
  if [[ ! -f "$manifest" ]]; then
    fail "$plugin: probe has no prerequisites.json"
    continue
  fi
  if cmp -s "$probe" "$first"; then
    pass "$plugin: probe is the shared manifest reader"
  else
    fail "$plugin: probe differs from ${first#"$REPO"/}"
  fi
  if grep -qE '(npm|pnpm|yarn|go|pip|brew|winget)[[:space:]]+(i|install|add|get)([[:space:]]|$)|npx ' "$probe"; then
    fail "$plugin: probe contains an install command"
  else
    pass "$plugin: probe contains no install command"
  fi

  data="$WORK/data-$plugin"
  out="$(cd "$WORK/cwd" && PATH="$WORK/sysbin" CLAUDE_PLUGIN_DATA="$data" \
    bash "$probe" <<<'{"session_id":"s1"}' 2>&1)"
  while IFS=$'\t' read -r name check install; do
    for want in "$name" "$check" "$install"; do
      if [[ "$out" == *"$want"* ]]; then
        pass "$plugin: missing $name notice names '$want'"
      else
        fail "$plugin: missing $name notice lacks '$want' (got: $out)"
      fi
    done
  done < <(jq -r '.tools[] | [.name, .check, .install] | @tsv' "$manifest")

  out="$(cd "$WORK/cwd" && PATH="$WORK/stubs:$WORK/sysbin" CLAUDE_PLUGIN_DATA="$WORK/data2-$plugin" \
    bash "$probe" <<<'{"session_id":"s1"}' 2>&1)"
  if [[ -z "$out" ]]; then
    pass "$plugin: silent when every declared tool is present"
  else
    fail "$plugin: expected no output with tools present, got: $out"
  fi
done

printf '%d cases, %d failed\n' "$CASES" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
