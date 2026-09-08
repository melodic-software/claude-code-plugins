#!/usr/bin/env bash
# Gate: every plugin this repo's catalog publishes must be enabled somewhere
# a cloud session on this repo reads, and its own enabled-plugin set must name
# only catalogued plugins.
#
#   scripts/check-plugin-catalog-enablement.sh   run the gate (no flags)
#
# WHY. docs/CLOUD-SESSIONS.md states the property this repo depends on: this
# repo dogfoods everything it publishes, so a regression in any plugin
# surfaces here first. Nothing enforced it. Three plugins reached main with a
# catalog entry and no `enabledPlugins` key -- ai-slop (#2892), context-budget
# (#2932) and improvement (#2985) -- while the plugin PRs on either side of
# them (coupling #2913, overengineering #2961) remembered the settings entry.
# The failure is silent by construction: a plugin nothing enables is simply
# never installed by .claude/cloud-bootstrap.sh, so the session comes up green
# with the plugin's skills missing and no line of output naming what is
# absent. That is the docs/conventions/liveness-assertion/ shape -- a
# documented guarantee with no gate behind it -- and it costs exactly the
# dogfooding the directory-source marketplace exists to provide.
#
# WHERE ENABLEMENT LIVES NOW. The fleet cloud plugin list in standards
# (components/cloud-environment/fleet-plugins.json) is what every cloud
# snapshot installs, and the bootstrap reads its snapshot copy overlaid with
# this repo's .claude/settings.json. So a catalogued plugin is covered when
# the fleet list enables it OR this file carries an explicit key for it, and
# this file no longer mirrors the whole catalog (that mirror was writing one
# project-scope install record per plugin per checkout on every local session
# start). The fleet list is fetched from its published URL at gate time; an
# unreachable list is a usage error, never a pass.
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
# WHAT IS CHECKED (both directions):
#   1. UNENABLED PLUGIN  -- a .claude-plugin/marketplace.json entry that the
#      fleet list does not enable AND that has no `<name>@<marketplace>` key
#      in .claude/settings.json `enabledPlugins`. The class that shipped
#      three times.
#   2. ORPHANED ENTRY    -- an `enabledPlugins` key for this marketplace that
#      names no catalog entry. What a plugin rename or removal leaves behind;
#      the id resolves to nothing and the install silently no-ops.
#   3. UNSORTED KEYS     -- `enabledPlugins` keys out of byte order. The same
#      doc calls the alphabetical one-per-line layout the reason a single
#      plugin can be flipped to `false` without disturbing the rest, and an
#      insertion at the wrong point is how a duplicate-looking near-miss hides.
#
# A key set to `false` PASSES. An explicit `false` is a recorded decision:
# the gate treats every matching settings key as coverage regardless of
# value, so a disable of a plugin the fleet list never enabled still
# passes. When the fleet list does enable that plugin, the bootstrap's
# overlay honors the `false` as an opt-out (settings-wins). An absent key
# is the drift this gate exists to name. The two are different states and
# only one of them is silent.
#
# Exit codes: 0 clean, 1 drift, 2 fatal (inputs missing or unreadable).
#
# Env overrides (tests only):
#   PLUGIN_CATALOG_ENABLEMENT_MARKETPLACE  -- path to marketplace.json
#   PLUGIN_CATALOG_ENABLEMENT_SETTINGS     -- path to settings.json
#   PLUGIN_CATALOG_ENABLEMENT_BOOTSTRAP    -- path to cloud-bootstrap.sh
#   PLUGIN_CATALOG_ENABLEMENT_FLEET        -- path to a local fleet list,
#                                             instead of fetching the URL
set -euo pipefail

FLEET_URL='https://raw.githubusercontent.com/melodic-software/standards/main/components/cloud-environment/fleet-plugins.json'

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
# marketplace's key and reporting the real plugin as unenabled. A gate whose
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

# The fleet list: a local path from the test seam, else the published file.
# Fetch failure is fatal (exit 2): a gate that cannot read the list it judges
# by must not report green.
fleet_tmp=''
if [[ -n "${PLUGIN_CATALOG_ENABLEMENT_FLEET:-}" ]]; then
  FLEET="$PLUGIN_CATALOG_ENABLEMENT_FLEET"
else
  fleet_tmp="$(mktemp)"
  trap 'rm -f "$fleet_tmp"' EXIT
  if ! curl -fsSL --proto '=https' --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 3 \
    "$FLEET_URL" -o "$fleet_tmp" 2>/dev/null; then
    printf 'check-plugin-catalog-enablement: could not fetch the fleet list from %s\n' "$FLEET_URL" >&2
    echo '  The gate judges catalog coverage against that list; without it a green result would be a guess.' >&2
    exit 2
  fi
  FLEET="$fleet_tmp"
fi
if ! jq -e 'type == "object" and ((.enabledPlugins // {}) | type == "object")' "$FLEET" >/dev/null 2>&1; then
  printf 'check-plugin-catalog-enablement: fleet list %s is not a settings-shaped JSON object\n' "$FLEET" >&2
  exit 2
fi
fleet_enabled="$(
  jq -r --arg mp "$MARKET" '.enabledPlugins // {} | to_entries[]
    | select(.value == true) | .key
    | select(endswith("@" + $mp)) | .[:length - ($mp | length) - 1]' "$FLEET" |
    tr -d '\r' | sort -u
)"
covered="$(printf '%s\n%s\n' "$enabled" "$fleet_enabled" | grep . | sort -u || true)"

errors=0

# 1. FORWARD -- catalogued but enabled nowhere.
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  printf "UNENABLED PLUGIN: %s catalogs '%s', but the fleet list does not enable '%s@%s' and %s enabledPlugins has no key for it.\n" \
    "$MARKETPLACE" "$name" "$name" "$MARKET" "$SETTINGS" >&2
  printf "  .claude/cloud-bootstrap.sh installs the fleet list overlaid with that file, so '%s' never loads in a session here.\n" \
    "$name" >&2
  printf "  Add it to the fleet list in standards (components/cloud-environment/fleet-plugins.json), or carry an explicit key here.\n" >&2
  errors=$((errors + 1))
done < <(comm -23 <(printf '%s\n' "$catalog") <(printf '%s\n' "$covered"))

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

# 4. IDENTITY -- the bootstrap must agree on which marketplace this is.
# This gate derives the suffix from extraKnownMarketplaces; .claude/cloud-
# bootstrap.sh hardcodes `marketplace_name` and selects its install set with
# endswith("@" + $n). Rename the marketplace and update both settings keys and
# the catalog, and the two disagree: `wanted` matches nothing, cloud sessions
# install none of the catalog, and this lane stays green over it -- a parity
# gate certifying a set nobody installs. Raised as P2 by the Codex review on
# #3235. Verifying the constant rather than deriving it keeps the bootstrap's
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
    echo "Every $MARKETPLACE entry must be enabled by the fleet list or carry an"
    echo "enabledPlugins key in $SETTINGS, and every enabledPlugins key for the"
    echo "'$MARKET' marketplace must name a catalogued plugin. A key set to false"
    echo "is a recorded decision and passes; a plugin nothing enables is drift."
    echo "$BOOTSTRAP must name that same marketplace, or what it installs and"
    echo "what this gate checks are two different sets."
  } >&2
  exit 1
fi

catalog_count="$(printf '%s\n' "$catalog" | grep -c . || true)"
echo "Every one of the $catalog_count catalogued plugins is enabled by the fleet list or carries an enabledPlugins key for '$MARKET'; none orphaned; keys sorted; $BOOTSTRAP installs that same marketplace."
