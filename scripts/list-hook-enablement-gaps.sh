#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2

NAME=list-hook-enablement-gaps

if ! command -v jq >/dev/null 2>&1; then
  echo "$NAME: jq is required but not installed" >&2
  exit 2
fi

HAS_HOOK='([(.hooks? // {}) | .[]? | .[]? | (.hooks? // [])[]?] | length) + ((.modules? // []) | length) > 0'
HAS_KEY='[(.userConfig // {}) | to_entries[] | select((.key | test("_enabled$")) and (.value | type) == "object" and .value.type == "boolean")] | length > 0'

scanned=0
gaps=()
for config in plugins/*/hooks/hooks.json; do
  [[ -f "$config" ]] || continue
  plugin="${config#plugins/}"
  plugin="${plugin%%/*}"
  has_hook="$(jq -r "$HAS_HOOK" "$config" 2>/dev/null | tr -d '\r')"
  if [[ "$has_hook" != true && "$has_hook" != false ]]; then
    echo "$NAME: $config is not readable JSON" >&2
    exit 2
  fi
  [[ "$has_hook" == true ]] || continue
  scanned=$((scanned + 1))
  manifest="plugins/$plugin/.claude-plugin/plugin.json"
  has_key=false
  if [[ -f "$manifest" ]]; then
    has_key="$(jq -r "$HAS_KEY" "$manifest" 2>/dev/null | tr -d '\r')"
    if [[ "$has_key" != true && "$has_key" != false ]]; then
      echo "$NAME: $manifest is not readable JSON" >&2
      exit 2
    fi
  fi
  [[ "$has_key" == true ]] || gaps+=("$plugin")
done

if ((scanned == 0)); then
  echo "$NAME: no plugins/*/hooks/hooks.json declares a hook; refusing to report an empty list" >&2
  exit 2
fi

if ((${#gaps[@]} > 0)); then
  printf '%s\n' "${gaps[@]}" | LC_ALL=C sort
fi
printf '%s: %d of %d plugin(s) with hooks declare no boolean <name>_enabled option\n' \
  "$NAME" "${#gaps[@]}" "$scanned" >&2
