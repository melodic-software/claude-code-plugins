#!/usr/bin/env bash
# Gate: this repo's committed enabled-plugin set must name only catalogued
# plugins, in byte order, and the cloud bootstrap must install the marketplace
# that set belongs to.
#
#   scripts/check-plugin-catalog-enablement.sh   run the gate (no flags)
#
# WHAT A CLOUD SESSION HERE INSTALLS. The cloud environment's setup (setup.sh
# in the standards repository, components/cloud-environment/) derives the
# fleet list every snapshot installs from this catalog: each entry whose
# `defaultEnabled` is absent or `true`. .claude/cloud-bootstrap.sh reads that
# list overlaid with .claude/settings.json, whose `enabledPlugins` block
# carries only this repo's deltas: `false` opts out of an on-by-default
# plugin, `true` opts in to an off-by-default one. Because the list comes from
# the catalog, no catalogued plugin can go missing unannounced: it is on by
# default, or the catalog records it as off. So this gate checks the deltas
# block, not per-plugin coverage. The block does not mirror the catalog: a
# mirror writes one project-scope install record per plugin per checkout on
# every local session start.
#
# NOT COVERED ELSEWHERE. plugins/harness-config/skills/audit/scripts/
# check-plugin-drift.sh audits this same axis for CONSUMER repos. It reads this
# repo's catalog too (a relative `directory` source), but it diffs the catalog
# only against the `enabledPlugins` keys of one settings file, reports a plugin
# with no key as NEW (report only, exit 0), and checks no key order, so it
# cannot gate this repo. scripts/check-plugin-manifest-presence.sh holds the
# catalog against the filesystem (manifest present, name matches, no
# unregistered directory).
#
# WHAT IS CHECKED:
#   1. ORPHANED ENTRY    -- an `enabledPlugins` key for this marketplace that
#      names no catalog entry. What a plugin rename or removal leaves behind;
#      the id resolves to nothing and the install silently no-ops.
#   2. UNSORTED KEYS     -- `enabledPlugins` keys out of byte order.
#      docs/cloud-sessions.md calls the alphabetical one-per-line layout the
#      reason a single plugin can be flipped without disturbing the rest, and
#      an insertion at the wrong point is how a duplicate-looking near-miss
#      hides.
#   3. IDENTITY          -- the bootstrap's `marketplace_name` must equal the
#      marketplace the settings file declares (see the check below).
#
# A key's value is not judged: `true` and `false` are both recorded deltas.
#
# Exit codes: 0 clean, 1 drift, 2 fatal (inputs missing or unreadable).
#
# Env overrides (tests only):
#   PLUGIN_CATALOG_ENABLEMENT_MARKETPLACE  -- path to marketplace.json
#   PLUGIN_CATALOG_ENABLEMENT_SETTINGS     -- path to settings.json
#   PLUGIN_CATALOG_ENABLEMENT_BOOTSTRAP    -- path to cloud-bootstrap.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "check-plugin-catalog-enablement: jq is required but not installed" >&2
  exit 2
fi

MARKETPLACE="${PLUGIN_CATALOG_ENABLEMENT_MARKETPLACE:-.claude-plugin/marketplace.json}"
SETTINGS="${PLUGIN_CATALOG_ENABLEMENT_SETTINGS:-.claude/settings.json}"
BOOTSTRAP="${PLUGIN_CATALOG_ENABLEMENT_BOOTSTRAP:-.claude/cloud-bootstrap.sh}"

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

if [[ ! -f "$BOOTSTRAP" ]]; then
  echo "check-plugin-catalog-enablement: $BOOTSTRAP not found" >&2
  echo "  Without it the marketplace-identity coherence check below cannot run, and a green" >&2
  echo "  result would overstate what this gate verified. Failing rather than skipping." >&2
  exit 2
fi

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

# Suffix stripping is a LITERAL parameter expansion, never a `sed` expression
# interpolating $MARKET. A marketplace name is free-form text from a settings
# file, so a regex metacharacter in it would change what the pattern matches
# rather than what it says: a name like 'melodic.software' would make the '.'
# match any character, silently accepting 'alpha@melodicXsoftware' as this
# marketplace's key and reporting it as an orphan. A gate whose
# whole purpose is to catch silent drift must not have a silent-wrongness path
# of its own. Flagged as informational (not a finding) by the security review
# on #3235, on the grounds that the value is repo-controlled and crosses no
# trust boundary -- true, and beside the point for correctness.
enabled="$(
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    [[ "$key" == *"@$MARKET" ]] || continue
    printf '%s\n' "${key%"@$MARKET"}"
  done <<<"$declared_keys" | sort -u
)"

errors=0

# 1. ORPHANS -- enabled but no longer catalogued.
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  printf "ORPHANED ENABLED ENTRY: %s enables '%s@%s', but %s catalogs no such plugin.\n" \
    "$SETTINGS" "$name" "$MARKET" "$MARKETPLACE" >&2
  printf "  The id resolves to nothing; the install silently no-ops. Drop the entry, or restore the catalog entry it names.\n" >&2
  errors=$((errors + 1))
done < <(comm -13 <(printf '%s\n' "$catalog") <(printf '%s\n' "$enabled"))

# 2. LAYOUT -- keys must stay in byte order, one per line.
if [[ -n "$declared_keys" ]]; then
  if ! diff <(printf '%s\n' "$declared_keys") <(printf '%s\n' "$declared_keys" | LC_ALL=C sort) >/dev/null; then
    printf 'UNSORTED enabledPlugins: keys in %s are not in byte order.\n' "$SETTINGS" >&2
    printf '  docs/cloud-sessions.md documents the alphabetical one-per-line layout as what lets a single\n' >&2
    printf '  plugin be flipped to false without disturbing the rest. First keys out of order:\n' >&2
    diff <(printf '%s\n' "$declared_keys") <(printf '%s\n' "$declared_keys" | LC_ALL=C sort) |
      sed -n '1,10p' | sed 's/^/    /' >&2
    errors=$((errors + 1))
  fi
fi

# 3. IDENTITY -- the bootstrap must agree on which marketplace this is.
# This gate derives the suffix from extraKnownMarketplaces; .claude/cloud-
# bootstrap.sh hardcodes `marketplace_name` and selects its install set with
# endswith("@" + $n). Rename the marketplace and update both settings keys and
# the catalog, and the two disagree: `wanted` matches nothing, cloud sessions
# install none of the catalog, and this lane stays green over it -- a parity
# gate certifying a set nobody installs. Verifying the constant rather than deriving it keeps the bootstrap's
# behavior byte-identical (it must work before anything else does) while making
# a rename that touches only one of the two impossible to merge.
bootstrap_name="$(sed -n 's/^marketplace_name="\([^"]*\)".*/\1/p' "$BOOTSTRAP" | head -1)"

if [[ -z "$bootstrap_name" ]]; then
  printf 'UNREADABLE BOOTSTRAP IDENTITY: %s declares no marketplace_name="..." assignment at line start.\n' \
    "$BOOTSTRAP" >&2
  printf '  This gate cannot confirm the bootstrap installs the marketplace it holds the catalog against.\n' >&2
  printf '  If the constant moved or was renamed, update this check with it.\n' >&2
  errors=$((errors + 1))
elif [[ "$bootstrap_name" != "$MARKET" ]]; then
  printf "MARKETPLACE IDENTITY MISMATCH: %s declares marketplace_name='%s', but %s declares the marketplace '%s'.\n" \
    "$BOOTSTRAP" "$bootstrap_name" "$SETTINGS" "$MARKET" >&2
  printf "  The bootstrap selects what it installs with endswith(\"@%s\"), so it would install none of the\n" \
    "$bootstrap_name" >&2
  printf "  '%s' catalog this gate just checked. Update both, or the parity below certifies a set nobody installs.\n" \
    "$MARKET" >&2
  errors=$((errors + 1))
fi

if ((errors > 0)); then
  {
    echo
    echo "Every enabledPlugins key in $SETTINGS for the '$MARKET' marketplace"
    echo "must name a $MARKETPLACE entry, with keys in byte order, and"
    echo "$BOOTSTRAP must name that same marketplace, or what it installs and"
    echo "what this gate checks are two different sets."
  } >&2
  exit 1
fi

catalog_count="$(printf '%s\n' "$catalog" | grep -c . || true)"
echo "Every enabledPlugins key for '$MARKET' names one of the $catalog_count catalogued plugins; none orphaned; keys sorted; $BOOTSTRAP installs that same marketplace."
