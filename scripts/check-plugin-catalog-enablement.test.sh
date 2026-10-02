#!/usr/bin/env bash
# Black-box contract test for check-plugin-catalog-enablement.sh.
#
# Self-contained and cwd-independent: builds throwaway marketplace.json and
# settings.json fixtures, runs the checker against them, and asserts on exit
# code plus the failure class named in the output. Mutates only its own
# mktemp dir.
#
# A green run on the current repo tree proves nothing about the gate -- the
# tree is green by construction once the drift is fixed. These fixtures prove
# it goes RED on an off-by-default plugin with no enabledPlugins key, on the inverse
# (an enabled id no catalog entry backs), and on unsorted keys; and that an
# explicit `false` still passes, because an off switch a gate rejects is an
# off switch nobody can use.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-plugin-catalog-enablement.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
TMP=""

fixture_tree::build TMP --sut "$SUT_SRC"
mkdir -p "$TMP/.claude-plugin" "$TMP/.claude"
SUT="$TMP/scripts/check-plugin-catalog-enablement.sh"
MARKETPLACE="$TMP/.claude-plugin/marketplace.json"
SETTINGS="$TMP/.claude/settings.json"

write_marketplace() {
  # one plugin per argument: `name` leaves defaultEnabled absent, and
  # `name=<json>` sets it to that literal JSON value (false, true, "false").
  {
    echo '{'
    echo '  "name": "fixture-marketplace",'
    echo '  "owner": {"name": "fixture"},'
    echo '  "plugins": ['
    local first=1 arg name extra
    for arg in "$@"; do
      if ((first)); then first=0; else echo ','; fi
      name="${arg%%=*}" extra=''
      [[ "$arg" == *=* ]] && extra=", \"defaultEnabled\": ${arg#*=}"
      printf '    {"name": "%s", "source": "./plugins/%s", "category": "development"%s}' "$name" "$name" "$extra"
    done
    echo
    echo '  ]'
    echo '}'
  } >"$MARKETPLACE"
}

write_settings() {
  # "<plugin> <true|false>" pairs on stdin, emitted in the order given so the
  # sort check sees exactly the layout the fixture asked for.
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
    echo '  },'
    echo '  "extraKnownMarketplaces": {'
    echo '    "fixture": {"source": {"source": "directory", "path": "./"}}'
    echo '  }'
    echo '}'
  } >"$SETTINGS"
}

write_bootstrap() {
  # the marketplace name the fixture bootstrap claims to install
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

# Every fixture below declares the "fixture" marketplace unless it overrides
# this, so the identity check agrees by default and each case exercises only
# the drift class it names.
write_bootstrap fixture

# --- 1. Happy path: defaultEnabled absent means covered with no key. --------
write_marketplace alpha beta gamma
printf '' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'none orphaned; keys sorted' <<<"$out"; then
  ok "a catalog with defaultEnabled absent passes with an empty enabledPlugins"
else
  fail "on-by-default catalog should pass (rc=$rc): $out"
fi

write_marketplace alpha=true beta
printf '' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "defaultEnabled true counts as on by default"
else
  fail "defaultEnabled true should be covered (rc=$rc): $out"
fi

# --- 2. Off by default with no key is enabled nowhere. ----------------------
write_marketplace alpha beta=false gamma
printf 'alpha true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNENABLED PLUGIN' <<<"$out" && grep -q "'beta'" <<<"$out" &&
  ! grep -q "'gamma'" <<<"$out"; then
  ok "a defaultEnabled false plugin with no settings key fails the gate"
else
  fail "off-by-default plugin with no key should fail (rc=$rc): $out"
fi

# The cloud derivation enables only absent or boolean true, so a mistyped
# string "false" is off there and must be off here.
write_marketplace alpha 'beta="false"'
printf '' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "'beta'" <<<"$out"; then
  ok "a non-boolean defaultEnabled counts as off by default"
else
  fail "string defaultEnabled should be off (rc=$rc): $out"
fi

# --- 3. Off by default with an explicit key, true or false, is covered. -----
write_marketplace alpha beta=false gamma=false
printf 'beta true\ngamma false\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "an off-by-default plugin with an explicit true or false key passes"
else
  fail "explicit key on an off-by-default plugin should pass (rc=$rc): $out"
fi

# A key under another marketplace does not cover this catalog.
write_marketplace alpha beta=false
{
  echo '{'
  echo '  "enabledPlugins": {"beta@other-market": true},'
  echo '  "extraKnownMarketplaces": {'
  echo '    "fixture": {"source": {"source": "directory", "path": "./"}}'
  echo '  }'
  echo '}'
} >"$SETTINGS"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "'beta'" <<<"$out"; then
  ok "a key under another marketplace does not cover an off-by-default plugin"
else
  fail "foreign-marketplace key must not count as coverage (rc=$rc): $out"
fi

# An explicit false on an on-by-default plugin is a recorded opt-out.
write_marketplace alpha beta gamma
printf 'alpha true\nbeta false\ngamma true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "a plugin explicitly disabled (false) still passes"
else
  fail "an explicit false should pass (rc=$rc): $out"
fi

# --- 4. Inverse: an enabled id the catalog no longer carries. ---------------
write_marketplace alpha gamma
printf 'alpha true\nbeta true\ngamma true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'ORPHANED ENABLED ENTRY' <<<"$out" && grep -q "'beta@fixture'" <<<"$out"; then
  ok "an enabledPlugins id with no catalog entry fails the gate"
else
  fail "orphaned enabled entry should fail (rc=$rc): $out"
fi

# --- 5. Keys out of byte order. ---------------------------------------------
write_marketplace alpha beta gamma
printf 'gamma true\nalpha true\nbeta true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNSORTED enabledPlugins' <<<"$out"; then
  ok "enabledPlugins keys out of byte order fail the gate"
else
  fail "unsorted keys should fail (rc=$rc): $out"
fi

# --- 6. Keys of another marketplace are none of this gate's business. -------
# Only the declared marketplace's suffix is compared; a foreign key must not
# read as an orphan. Two declared marketplaces is a different (fatal) case,
# covered in 7 -- here the second id is simply a suffix this repo's single
# marketplace does not own.
write_marketplace alpha beta
{
  echo '{'
  echo '  "enabledPlugins": {'
  echo '    "alpha@fixture": true,'
  echo '    "beta@fixture": true,'
  echo '    "zeta@other-market": true'
  echo '  },'
  echo '  "extraKnownMarketplaces": {'
  echo '    "fixture": {"source": {"source": "directory", "path": "./"}}'
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

# --- 6b. A regex metacharacter in the marketplace name stays literal. -------
# Suffix stripping must be a literal match, not a pattern. Under a pattern such
# as `sed -n "s/@$MARKET\$//p"` the '.' in 'melodic.software' matches any
# character, so 'alpha@melodicXsoftware' is accepted as this marketplace's
# key and the genuine 'alpha@melodic.software' entry goes unnoticed -- the
# gate reporting drift that does not exist while missing the shape it exists
# to catch.
write_marketplace alpha
write_bootstrap 'melodic.software'
{
  echo '{'
  echo '  "enabledPlugins": {'
  echo '    "alpha@melodic.software": true,'
  echo '    "beta@melodicXsoftware": true'
  echo '  },'
  echo '  "extraKnownMarketplaces": {'
  echo '    "melodic.software": {"source": {"source": "directory", "path": "./"}}'
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
write_bootstrap fixture

# --- 6c. The bootstrap must install the marketplace the gate checks. --------
# .claude/cloud-bootstrap.sh hardcodes `marketplace_name` and selects its
# install set with endswith("@" + $n), while this gate derives the suffix from
# extraKnownMarketplaces. A rename that updates settings and catalog but not
# the bootstrap leaves `wanted` empty -- cloud sessions install none of the
# catalog -- with this lane green over it.
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

# A bootstrap whose constant moved or was renamed cannot be verified, and a
# green result would overstate what ran -- so it fails rather than skipping.
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

# --- 7. Ambiguous input is fatal, not a guess. ------------------------------
write_marketplace alpha
{
  echo '{'
  echo '  "enabledPlugins": {"alpha@fixture": true},'
  echo '  "extraKnownMarketplaces": {'
  echo '    "fixture": {"source": {"source": "directory", "path": "./"}},'
  echo '    "second": {"source": {"source": "github", "repo": "o/r"}}'
  echo '  }'
  echo '}'
} >"$SETTINGS"
out="$(run)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'expected exactly one entry' <<<"$out"; then
  ok "two declared marketplaces is fatal rather than a guess"
else
  fail "ambiguous marketplace set should exit 2 (rc=$rc): $out"
fi

# --- 8. Unreadable inputs are fatal, not silently green. --------------------
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
