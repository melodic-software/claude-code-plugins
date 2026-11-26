#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-plugin-catalog-enablement.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

TMP=""

fixture_tree::build TMP --sut "$SUT_SRC"
mkdir -p "$TMP/.claude-plugin" "$TMP/.claude"
SUT="$TMP/scripts/check-plugin-catalog-enablement.sh"
MARKETPLACE="$TMP/.claude-plugin/marketplace.json"
SETTINGS="$TMP/.claude/settings.json"

market_name=fixture

write_marketplace() {
  {
    echo '{'
    printf '  "name": "%s",\n' "$market_name"
    echo '  "owner": {"name": "fixture"},'
    echo '  "plugins": ['
    local first=1 name
    for name in "$@"; do
      if ((first)); then first=0; else echo ','; fi
      printf '    {"name": "%s", "source": "./plugins/%s", "category": "development"}' "$name" "$name"
    done
    echo
    echo '  ]'
    echo '}'
  } >"$MARKETPLACE"
}

write_settings() {
  {
    echo '{'
    echo '  "enabledPlugins": {'
    local first=1 name value
    while read -r name value; do
      [[ -n "$name" ]] || continue
      if ((first)); then first=0; else echo ','; fi
      printf '    "%s@fixture": %s' "$name" "$value"
    done
    echo
    echo '  }'
    echo '}'
  } >"$SETTINGS"
}

write_bootstrap() {
  printf '#!/usr/bin/env bash\nmarketplace_name="%s"\n' "$1" >"$TMP/.claude/cloud-bootstrap.sh"
}

run() {
  (
    cd "$TMP" &&
      PLUGIN_CATALOG_ENABLEMENT_MARKETPLACE=".claude-plugin/marketplace.json" \
        PLUGIN_CATALOG_ENABLEMENT_SETTINGS=".claude/settings.json" \
        PLUGIN_CATALOG_ENABLEMENT_BOOTSTRAP=".claude/cloud-bootstrap.sh" \
        bash "$SUT" 2>&1
  )
}

write_bootstrap fixture

write_marketplace alpha beta gamma
printf 'alpha true\nbeta true\ngamma true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'none orphaned; keys sorted' <<<"$out" &&
  ! grep -q extraKnownMarketplaces "$SETTINGS"; then
  ok "catalog and enabledPlugins in agreement pass with no extraKnownMarketplaces in settings"
else
  fail "happy path should pass (rc=$rc): $out"
fi

write_marketplace alpha beta gamma
printf 'beta false\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "catalogued plugins with no enabledPlugins key pass"
else
  fail "a deltas-only settings block should pass (rc=$rc): $out"
fi

write_marketplace alpha beta gamma
printf 'alpha true\nbeta false\ngamma true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "a plugin explicitly disabled (false) still passes"
else
  fail "an explicit false should pass (rc=$rc): $out"
fi

write_marketplace alpha gamma
printf 'alpha true\nbeta true\ngamma true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'ORPHANED ENABLED ENTRY' <<<"$out" && grep -q "'beta@fixture'" <<<"$out"; then
  ok "an enabledPlugins id with no catalog entry fails the gate"
else
  fail "orphaned enabled entry should fail (rc=$rc): $out"
fi

write_marketplace alpha beta gamma
printf 'gamma true\nalpha true\nbeta true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNSORTED enabledPlugins' <<<"$out"; then
  ok "enabledPlugins keys out of byte order fail the gate"
else
  fail "unsorted keys should fail (rc=$rc): $out"
fi

write_marketplace alpha beta
{
  echo '{'
  echo '  "enabledPlugins": {'
  echo '    "alpha@fixture": true,'
  echo '    "beta@fixture": true,'
  echo '    "zeta@other-market": true'
  echo '  }'
  echo '}'
} >"$SETTINGS"
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "an enabledPlugins key for a different marketplace is ignored"
else
  fail "foreign-marketplace key should not fail the gate (rc=$rc): $out"
fi

market_name='melodic.software'
write_marketplace alpha
write_bootstrap 'melodic.software'
{
  echo '{'
  echo '  "enabledPlugins": {'
  echo '    "alpha@melodic.software": true,'
  echo '    "beta@melodicXsoftware": true'
  echo '  }'
  echo '}'
} >"$SETTINGS"
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "a regex metacharacter in the marketplace name is matched literally"
else
  fail "'.' in the marketplace name must not match any character (rc=$rc): $out"
fi
market_name=fixture
write_bootstrap fixture

write_marketplace alpha beta
printf 'alpha true\nbeta true\n' | write_settings
write_bootstrap old-market-name
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'MARKETPLACE IDENTITY MISMATCH' <<<"$out"; then
  ok "a bootstrap naming a different marketplace fails the gate"
else
  fail "bootstrap/settings marketplace mismatch should fail (rc=$rc): $out"
fi

printf '#!/usr/bin/env bash\n# no marketplace_name assignment here\n' >"$TMP/.claude/cloud-bootstrap.sh"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNREADABLE BOOTSTRAP IDENTITY' <<<"$out"; then
  ok "a bootstrap with no marketplace_name assignment fails rather than skipping"
else
  fail "unreadable bootstrap identity should fail (rc=$rc): $out"
fi

rm -f "$TMP/.claude/cloud-bootstrap.sh"
out="$(run)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'cloud-bootstrap.sh not found' <<<"$out"; then
  ok "a missing bootstrap exits 2 rather than passing silently"
else
  fail "missing bootstrap should exit 2 (rc=$rc): $out"
fi
write_bootstrap fixture

write_marketplace alpha
{
  echo '{'
  echo '  "enabledPlugins": {"alpha@fixture": true},'
  echo '  "extraKnownMarketplaces": {'
  echo '    "other": {"source": {"source": "directory", "path": "./"}},'
  echo '    "second": {"source": {"source": "github", "repo": "o/r"}}'
  echo '  }'
  echo '}'
} >"$SETTINGS"
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "for 'fixture'" <<<"$out"; then
  ok "the marketplace name is read from marketplace.json, not extraKnownMarketplaces"
else
  fail "settings marketplaces should not decide the name (rc=$rc): $out"
fi

write_marketplace alpha
{
  echo '{'
  echo '  "enabledPlugins": {"alpha@fixture": true},'
  echo '  "extraKnownMarketplaces": {'
  echo '    "fixture": {"source": {"source": "directory", "path": "./"}},'
  echo '    "other": {"source": {"source": "github", "repo": "o/r"}}'
  echo '  }'
  echo '}'
} >"$SETTINGS"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'SHADOWED MARKETPLACE' <<<"$out" && grep -q "'fixture'" <<<"$out"; then
  ok "settings redeclaring the catalog's marketplace in extraKnownMarketplaces fails the gate"
else
  fail "extraKnownMarketplaces naming the catalog's marketplace should fail (rc=$rc): $out"
fi

market_name=''
write_marketplace alpha
market_name=fixture
printf 'alpha true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'declares no name' <<<"$out"; then
  ok "a marketplace.json with an empty name exits 2"
else
  fail "a nameless marketplace.json should exit 2 (rc=$rc): $out"
fi

write_marketplace alpha
printf 'alpha true\n' | write_settings
printf 'not json\n' >"$SETTINGS"
out="$(run)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'not valid JSON' <<<"$out"; then
  ok "invalid settings JSON exits 2"
else
  fail "invalid settings JSON should exit 2 (rc=$rc): $out"
fi

write_marketplace alpha
printf 'alpha true\n' | write_settings
rm -f "$MARKETPLACE"
out="$(run)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'not found' <<<"$out"; then
  ok "a missing marketplace.json exits 2"
else
  fail "missing marketplace.json should exit 2 (rc=$rc): $out"
fi

test_harness::report
