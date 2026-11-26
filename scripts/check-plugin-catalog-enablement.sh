#!/usr/bin/env bash
# Exit codes: 0 clean, 1 drift, 2 fatal (inputs missing or unreadable).
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

MARKET="$(jq -r '.name // empty' "$MARKETPLACE" | tr -d '\r')"

if [[ -z "$MARKET" ]]; then
  echo "check-plugin-catalog-enablement: $MARKETPLACE declares no name" >&2
  echo "  The enabledPlugins keys this gate checks are '<plugin>@<marketplace name>'; without it there is nothing to hold them against." >&2
  exit 2
fi

catalog="$(jq -r '.plugins[]?.name // empty' "$MARKETPLACE" | tr -d '\r' | sort -u)"

if [[ -z "$catalog" ]]; then
  echo "check-plugin-catalog-enablement: $MARKETPLACE lists no plugins" >&2
  exit 2
fi

declared_keys="$(jq -r '.enabledPlugins // {} | keys_unsorted[]' "$SETTINGS" | tr -d '\r')"

enabled="$(
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    [[ "$key" == *"@$MARKET" ]] || continue
    printf '%s\n' "${key%"@$MARKET"}"
  done <<<"$declared_keys" | sort -u
)"

errors=0

while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  printf "ORPHANED ENABLED ENTRY: %s enables '%s@%s', but %s catalogs no such plugin.\n" \
    "$SETTINGS" "$name" "$MARKET" "$MARKETPLACE" >&2
  printf "  The id resolves to nothing; the install silently no-ops. Drop the entry, or restore the catalog entry it names.\n" >&2
  errors=$((errors + 1))
done < <(comm -13 <(printf '%s\n' "$catalog") <(printf '%s\n' "$enabled"))

sorted_keys="$(printf '%s\n' "$declared_keys" | LC_ALL=C sort)"
if [[ "$declared_keys" != "$sorted_keys" ]]; then
  printf 'UNSORTED enabledPlugins: keys in %s are not in byte order.\n' "$SETTINGS" >&2
  printf '  docs/cloud-sessions.md documents the alphabetical one-per-line layout as what lets a single\n' >&2
  printf '  plugin be flipped to false without disturbing the rest. First keys out of order:\n' >&2
  diff <(printf '%s\n' "$declared_keys") <(printf '%s\n' "$sorted_keys") |
    sed -n '1,10p' | sed 's/^/    /' >&2
  errors=$((errors + 1))
fi

bootstrap_name="$(sed -n 's/^marketplace_name="\([^"]*\)".*/\1/p' "$BOOTSTRAP" | head -1)"

if [[ -z "$bootstrap_name" ]]; then
  printf 'UNREADABLE BOOTSTRAP IDENTITY: %s declares no marketplace_name="..." assignment at line start.\n' \
    "$BOOTSTRAP" >&2
  printf '  This gate cannot confirm the bootstrap installs the marketplace it holds the catalog against.\n' >&2
  printf '  If the constant moved or was renamed, update this check with it.\n' >&2
  errors=$((errors + 1))
elif [[ "$bootstrap_name" != "$MARKET" ]]; then
  printf "MARKETPLACE IDENTITY MISMATCH: %s declares marketplace_name='%s', but %s names the marketplace '%s'.\n" \
    "$BOOTSTRAP" "$bootstrap_name" "$MARKETPLACE" "$MARKET" >&2
  printf "  The bootstrap selects what it installs with endswith(\"@%s\"), so it would install none of the\n" \
    "$bootstrap_name" >&2
  printf "  '%s' catalog this gate just checked. Update both, or the parity below certifies a set nobody installs.\n" \
    "$MARKET" >&2
  errors=$((errors + 1))
fi

if jq -e --arg m "$MARKET" '(.extraKnownMarketplaces // {}) | has($m)' "$SETTINGS" >/dev/null; then
  printf "SHADOWED MARKETPLACE: %s declares extraKnownMarketplaces.'%s', the marketplace %s names.\n" \
    "$SETTINGS" "$MARKET" "$MARKETPLACE" >&2
  printf '  Local sessions resolve it from the user registration and the cloud bootstrap registers it;\n' >&2
  printf '  a project entry overrides both. Remove it.\n' >&2
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
