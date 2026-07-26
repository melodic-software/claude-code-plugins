#!/usr/bin/env bash
# Gate: every plugin directory the catalog references must carry a readable
# .claude-plugin/plugin.json whose own "name" matches the catalog key, and
# every plugins/*/ directory must be registered in the catalog.
#
#   scripts/check-plugin-manifest-presence.sh   run the gate (no flags)
#
# Why: #1547 -- a routine `git merge origin/main` silently dropped
# plugins/guardrails/.claude-plugin/plugin.json for ~14 minutes on a branch
# while .claude-plugin/marketplace.json still pointed the "guardrails" catalog
# key at that directory. No conflict markers, nothing to alert the author; it
# was caught by an AI reviewer reading the diff, not by CI. Consequences of a
# missing manifest are otherwise all deferred to install time: a fresh
# install or marketplace update cannot load the plugin, and the version the
# CHANGELOG claims is never published.
#
# Not covered by scripts/check-manifest-duplicate-keys.py (#1506/#1498): that
# validates the CONTENTS of a manifest that exists. This is about one that
# does not.
#
# Two checks, both static and repo-wide:
#   1. FORWARD  -- for every .claude-plugin/marketplace.json entry, the
#      directory its "source" names must contain a readable
#      .claude-plugin/plugin.json, and that manifest's own "name" must equal
#      the catalog key. A missing manifest and a name/key mismatch are
#      reported as distinct failure classes.
#   2. INVERSE  -- every plugins/*/ directory must be named by some catalog
#      entry's "source". Lower severity (an orphaned directory cannot break an
#      install the way a missing manifest can) but the same class of drift in
#      the other direction, so it is cheap to catch here too.
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

# name<TAB>source, one per catalog entry. CRLF tolerance: on Windows (Git
# Bash) jq can emit \r\n line endings, which a bare herestring `read` loop
# would otherwise leak into $source (as a trailing \r invisible in most
# terminal output) and turn every directory/file lookup below into a false
# MISSING failure.
entries="$(jq -r '.plugins[] | [.name, .source] | @tsv' "$MARKETPLACE" | tr -d '\r')"

# Sources actually seen in the catalog, keyed by the normalized (leading
# "./" stripped) relative path -- used by the inverse check below.
declare -A catalog_sources=()

while IFS=$'\t' read -r name source; do
  [[ -n "$name" ]] || continue
  rel="${source#./}"
  catalog_sources["$rel"]=1

  dir="$rel"
  manifest="$dir/.claude-plugin/plugin.json"

  if [[ ! -d "$dir" ]]; then
    echo "MISSING PLUGIN DIRECTORY: catalog entry '$name' points $MARKETPLACE at '$source', but that directory does not exist." >&2
    errors=$((errors + 1))
    continue
  fi

  if [[ ! -f "$manifest" ]]; then
    echo "MISSING MANIFEST: catalog entry '$name' points $MARKETPLACE at '$source', but $manifest does not exist (or is not a regular file)." >&2
    echo "  A fresh install or marketplace update cannot load '$name' without it." >&2
    errors=$((errors + 1))
    continue
  fi

  manifest_name="$(jq -r '.name // empty' "$manifest" 2>/dev/null | tr -d '\r' || true)"
  if [[ -z "$manifest_name" ]]; then
    echo "MALFORMED MANIFEST: $manifest has no readable \"name\" field (catalog key: '$name')." >&2
    errors=$((errors + 1))
    continue
  fi

  if [[ "$manifest_name" != "$name" ]]; then
    echo "NAME MISMATCH: $MARKETPLACE catalogs '$name' at '$source', but $manifest declares \"name\": \"$manifest_name\"." >&2
    errors=$((errors + 1))
  fi
done <<<"$entries"

# Inverse check: every plugins/*/ directory must be named by some catalog
# entry's source. Lower severity than the forward check (an orphaned
# directory is dead weight, not a broken install) but the same class of
# catalog/filesystem drift, so it is checked here too.
if [[ -d "$PLUGINS_ROOT" ]]; then
  for plugin_dir in "$PLUGINS_ROOT"/*/; do
    [[ -d "$plugin_dir" ]] || continue
    rel="${plugin_dir%/}"
    if [[ -z "${catalog_sources[$rel]:-}" ]]; then
      echo "UNREGISTERED PLUGIN DIRECTORY: '$rel' exists but no $MARKETPLACE entry names it as its source." >&2
      errors=$((errors + 1))
    fi
  done
fi

if ((errors > 0)); then
  {
    echo
    echo "Every $MARKETPLACE entry must resolve to a plugin directory that"
    echo "carries a readable .claude-plugin/plugin.json whose own \"name\""
    echo "matches the catalog key, and every plugin directory must be"
    echo "registered in the catalog."
  } >&2
  exit 1
fi

echo "Every catalog entry resolves to a present, name-matching plugin manifest; no unregistered plugin directories."
