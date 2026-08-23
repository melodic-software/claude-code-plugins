#!/usr/bin/env bash
# Gate: this repo's own catalog and its own enabled-plugin set must name the
# same plugins.
#
#   scripts/check-plugin-catalog-enablement.sh   run the gate (no flags)
#
# WHY. docs/CLOUD-SESSIONS.md states the property this repo depends on:
# "`enabledPlugins` turns on the whole catalog, so this repo dogfoods
# everything it publishes and a regression in any plugin surfaces here first."
# Nothing enforced it. Three plugins reached main with a catalog entry and no
# `enabledPlugins` key -- ai-slop (#2892), context-budget (#2932) and
# improvement (#2985) -- while the plugin PRs on either side of them
# (coupling #2913, overengineering #2961) remembered the settings entry. The
# failure is silent by construction: a plugin absent from `enabledPlugins` is
# simply never installed by .claude/cloud-bootstrap.sh, whose wanted-set is
# computed from that same file, so the session comes up green with the
# plugin's skills missing and no line of output naming what is absent. That is
# the docs/conventions/liveness-assertion/ shape -- a documented guarantee with
# no gate behind it -- and it costs exactly the dogfooding the directory-source
# marketplace exists to provide.
#
# NOT COVERED ELSEWHERE. plugins/claude-config/skills/audit/scripts/
# check-plugin-drift.sh audits this same axis for CONSUMER repos, but it
# resolves each marketplace through `source.repo` and records SKIP for a
# marketplace that declares none. This repo's marketplace is a relative
# `directory` source with no `repo` field, so that detector structurally
# cannot see this repo's own drift. scripts/check-plugin-manifest-presence.sh
# holds the catalog against the filesystem (manifest present, name matches,
# no unregistered directory); it says nothing about whether a catalogued
# plugin is ever enabled.
#
# WHAT IS CHECKED (both directions, so the two sets are provably equal):
#   1. UNENABLED PLUGIN  -- a .claude-plugin/marketplace.json entry with no
#      `<name>@<marketplace>` key in .claude/settings.json `enabledPlugins`.
#      The class that shipped three times.
#   2. ORPHANED ENTRY    -- an `enabledPlugins` key for this marketplace that
#      names no catalog entry. What a plugin rename or removal leaves behind;
#      the id resolves to nothing and the install silently no-ops.
#   3. UNSORTED KEYS     -- `enabledPlugins` keys out of byte order. The same
#      doc calls the alphabetical one-per-line layout the reason a single
#      plugin can be flipped to `false` without disturbing the rest, and an
#      insertion at the wrong point is how a duplicate-looking near-miss hides.
#
# A key set to `false` PASSES. An explicit `false` is a recorded decision --
# the documented off switch for the two entries whose MCP servers need
# credentials this environment has no reason to hold (`miro`, `dometrain`) --
# whereas an absent key is the drift this gate exists to name. The two are
# different states and only one of them is silent.
#
# Exit codes: 0 clean, 1 drift, 2 fatal (inputs missing or unreadable).
#
# Env overrides (tests only):
#   PLUGIN_CATALOG_ENABLEMENT_MARKETPLACE  -- path to marketplace.json
#   PLUGIN_CATALOG_ENABLEMENT_SETTINGS     -- path to settings.json
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "check-plugin-catalog-enablement: jq is required but not installed" >&2
  exit 2
fi

MARKETPLACE="${PLUGIN_CATALOG_ENABLEMENT_MARKETPLACE:-.claude-plugin/marketplace.json}"
SETTINGS="${PLUGIN_CATALOG_ENABLEMENT_SETTINGS:-.claude/settings.json}"

for f in "$MARKETPLACE" "$SETTINGS"; do
  if [[ ! -f "$f" ]]; then
    echo "check-plugin-catalog-enablement: $f not found" >&2
    exit 2
  fi
  if ! jq empty "$f" 2>/dev/null; then
    echo "check-plugin-catalog-enablement: $f is not valid JSON" >&2
    exit 2
  fi
done

# The marketplace this repo declares for itself. Derived rather than
# hardcoded, so renaming the marketplace does not leave the gate silently
# checking a suffix nothing uses any more. Exactly one is expected: a second
# would make "the catalog" ambiguous, and guessing which one to hold the
# catalog against is how a gate goes quietly wrong.
mapfile -t market_keys < <(jq -r '.extraKnownMarketplaces // {} | keys[]' "$SETTINGS" | tr -d '\r')

if ((${#market_keys[@]} != 1)); then
  printf 'check-plugin-catalog-enablement: expected exactly one entry in %s extraKnownMarketplaces, found %d.\n' \
    "$SETTINGS" "${#market_keys[@]}" >&2
  printf '  This gate holds %s against the plugins this repo enables for itself;\n' "$MARKETPLACE" >&2
  printf '  with %d marketplaces declared there is no single set to hold it against.\n' "${#market_keys[@]}" >&2
  exit 2
fi

MARKET="${market_keys[0]}"

# CRLF tolerance: jq on Windows (Git Bash) can emit \r\n, and a trailing \r
# would ride into every comparison below as an invisible suffix mismatch.
catalog="$(jq -r '.plugins[]?.name // empty' "$MARKETPLACE" | tr -d '\r' | sort -u)"

if [[ -z "$catalog" ]]; then
  echo "check-plugin-catalog-enablement: $MARKETPLACE lists no plugins" >&2
  exit 2
fi

# Keys in declaration order (for the sort check) and the plugin names they
# carry for this marketplace (for the set comparisons).
declared_keys="$(jq -r '.enabledPlugins // {} | keys_unsorted[]' "$SETTINGS" | tr -d '\r')"
enabled="$(printf '%s\n' "$declared_keys" |
  sed -n "s/@${MARKET}\$//p" | sort -u)"

errors=0

# 1. FORWARD -- catalogued but never enabled.
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  printf "UNENABLED PLUGIN: %s catalogs '%s', but %s enabledPlugins has no '%s@%s' key.\n" \
    "$MARKETPLACE" "$name" "$SETTINGS" "$name" "$MARKET" >&2
  printf "  .claude/cloud-bootstrap.sh computes what it installs from that file, so '%s' never loads in a session here.\n" \
    "$name" >&2
  errors=$((errors + 1))
done < <(comm -23 <(printf '%s\n' "$catalog") <(printf '%s\n' "$enabled"))

# 2. INVERSE -- enabled but no longer catalogued.
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  printf "ORPHANED ENABLED ENTRY: %s enables '%s@%s', but %s catalogs no such plugin.\n" \
    "$SETTINGS" "$name" "$MARKET" "$MARKETPLACE" >&2
  printf "  The id resolves to nothing; the install silently no-ops. Drop the entry, or restore the catalog entry it names.\n" >&2
  errors=$((errors + 1))
done < <(comm -13 <(printf '%s\n' "$catalog") <(printf '%s\n' "$enabled"))

# 3. LAYOUT -- keys must stay in byte order, one per line.
if [[ -n "$declared_keys" ]]; then
  if ! diff <(printf '%s\n' "$declared_keys") <(printf '%s\n' "$declared_keys" | LC_ALL=C sort) >/dev/null; then
    printf 'UNSORTED enabledPlugins: keys in %s are not in byte order.\n' "$SETTINGS" >&2
    printf '  docs/CLOUD-SESSIONS.md documents the alphabetical one-per-line layout as what lets a single\n' >&2
    printf '  plugin be flipped to false without disturbing the rest. First keys out of order:\n' >&2
    diff <(printf '%s\n' "$declared_keys") <(printf '%s\n' "$declared_keys" | LC_ALL=C sort) |
      sed -n '1,10p' | sed 's/^/    /' >&2
    errors=$((errors + 1))
  fi
fi

if ((errors > 0)); then
  {
    echo
    echo "Every $MARKETPLACE entry must carry an enabledPlugins key in"
    echo "$SETTINGS, and every enabledPlugins key for the '$MARKET'"
    echo "marketplace must name a catalogued plugin. A key set to false is a"
    echo "recorded decision and passes; an absent key is drift and does not."
  } >&2
  exit 1
fi

catalog_count="$(printf '%s\n' "$catalog" | grep -c . || true)"
echo "Every one of the $catalog_count catalogued plugins carries an enabledPlugins key for '$MARKET'; none orphaned; keys sorted."
