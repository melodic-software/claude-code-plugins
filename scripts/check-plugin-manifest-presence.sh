#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "check-plugin-manifest-presence: jq is required but not installed" >&2
  exit 2
fi

MARKETPLACE="${PLUGIN_MANIFEST_PRESENCE_MARKETPLACE:-.claude-plugin/marketplace.json}"
PLUGINS_ROOT="${PLUGIN_MANIFEST_PRESENCE_PLUGINS_ROOT:-plugins}"

if [[ ! -f "$MARKETPLACE" ]]; then
  echo "check-plugin-manifest-presence: $MARKETPLACE not found" >&2
  exit 2
fi

errors=0

entries="$(jq -r '.plugins[] | [.name, .source] | @tsv' "$MARKETPLACE" | tr -d '\r')"

normalize_rel_path() {
  local raw="$1" out="" seg prefix=""
  local -a parts=()
  [[ "$raw" == /* ]] && prefix=/
  IFS=/ read -r -a parts <<<"$raw"
  for seg in ${parts[@]+"${parts[@]}"}; do
    [[ -n "$seg" && "$seg" != "." ]] || continue
    out="${out:+$out/}$seg"
  done
  printf '%s' "${prefix}${out:-.}"
}

declare -A catalog_sources=()

while IFS=$'\t' read -r name source; do
  [[ -n "$name" ]] || continue
  rel="$(normalize_rel_path "$source")"

  if [[ "$rel" == /* || "$rel" =~ ^[A-Za-z]: || "/$rel/" == *"/../"* ]]; then
    printf 'UNSAFE CATALOG SOURCE: %s entry %s has source %s, which resolves outside the repository -- refusing to probe it.\n' \
      "$MARKETPLACE" "$name" "$source" >&2
    errors=$((errors + 1))
    continue
  fi

  catalog_sources["$rel"]=1

  manifest="$rel/.claude-plugin/plugin.json"

  if [[ ! -d "$rel" ]]; then
    printf "MISSING PLUGIN DIRECTORY: catalog entry '%s' points %s at '%s', but that directory does not exist.\n" \
      "$name" "$MARKETPLACE" "$source" >&2
    errors=$((errors + 1))
    continue
  fi

  if [[ ! -f "$manifest" ]]; then
    printf "MISSING MANIFEST: catalog entry '%s' points %s at '%s', but %s does not exist (or is not a regular file).\n" \
      "$name" "$MARKETPLACE" "$source" "$manifest" >&2
    printf "  A fresh install or marketplace update cannot load '%s' without it.\n" "$name" >&2
    errors=$((errors + 1))
    continue
  fi

  manifest_name="$(jq -r '.name // empty' "$manifest" 2>/dev/null | tr -d '\r' || true)"
  if [[ -z "$manifest_name" ]]; then
    printf "MALFORMED MANIFEST: %s has no readable \"name\" field (catalog key: '%s').\n" "$manifest" "$name" >&2
    errors=$((errors + 1))
    continue
  fi

  if [[ "$manifest_name" != "$name" ]]; then
    printf "NAME MISMATCH: %s catalogs '%s' at '%s', but %s declares \"name\": \"%s\".\n" \
      "$MARKETPLACE" "$name" "$source" "$manifest" "$manifest_name" >&2
    errors=$((errors + 1))
  fi
done <<<"$entries"

if [[ -d "$PLUGINS_ROOT" ]]; then
  for plugin_dir in "$PLUGINS_ROOT"/*/; do
    [[ -d "$plugin_dir" ]] || continue
    rel="$(normalize_rel_path "$plugin_dir")"
    if [[ -z "${catalog_sources[$rel]:-}" ]]; then
      printf "UNREGISTERED PLUGIN DIRECTORY: '%s' exists but no %s entry names it as its source.\n" "$rel" "$MARKETPLACE" >&2
      errors=$((errors + 1))
    fi
  done

  for plugin_dir in "$PLUGINS_ROOT"/*/; do
    [[ -d "$plugin_dir" ]] || continue
    bin_path="${plugin_dir%/}/bin"
    # its command must be on PATH; org sync skips it: https://claude.com/docs/plugins/org-sync
    if [[ "$(basename "$plugin_dir")" == external-agents && -d "$bin_path" && ! -L "$bin_path" &&
      "$(find "$bin_path" -mindepth 1 -print)" == "$bin_path/external-agents" ]]; then
      continue
    fi
    if [[ -d "$bin_path" && ! -L "$bin_path" ]]; then
      [[ -n "$(find "$bin_path" -mindepth 1 -print -quit 2>/dev/null)" ]] || continue
    elif [[ ! -e "$bin_path" && ! -L "$bin_path" ]]; then
      continue
    fi
    printf "TOP-LEVEL BIN DIRECTORY: '%s' exists; claude.ai organization plugin sync rejects a plugin with a top-level bin/. Move its contents under scripts/.\n" "$bin_path" >&2
    errors=$((errors + 1))
  done
fi

if ((errors > 0)); then
  {
    echo
    echo "Every $MARKETPLACE entry must resolve to a plugin directory that"
    echo "carries a readable .claude-plugin/plugin.json whose own \"name\""
    echo "matches the catalog key, every plugin directory must be"
    echo "registered in the catalog, and no plugin but external-agents may have a top-level bin/."
  } >&2
  exit 1
fi

echo "Every catalog entry resolves to a present, name-matching plugin manifest; no unregistered plugin directories; no top-level bin/ outside external-agents."
