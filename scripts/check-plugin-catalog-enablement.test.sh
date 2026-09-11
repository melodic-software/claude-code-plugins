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
# it goes RED on the class that actually shipped (a catalogued plugin with no
# enabledPlugins key, three times: #2892, #2932, #2985), on the inverse
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
  # plugin names, one per argument
  {
    echo '{'
    echo '  "name": "fixture-marketplace",'
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

FLEET="$TMP/fleet.json"
write_fleet() {
  # "<plugin>@<marketplace>" ids the fixture fleet list enables, one per
  # argument; no arguments writes an empty list.
  {
    echo '{'
    echo '  "extraKnownMarketplaces": {'
    echo '    "fixture": {"source": {"source": "github", "repo": "o/r"}}'
    echo '  },'
    echo '  "enabledPlugins": {'
    local first=1 id
    for id in "$@"; do
      if ((first)); then first=0; else echo ','; fi
      printf '    "%s": true' "$id"
    done
    echo
    echo '  }'
    echo '}'
  } >"$FLEET"
}

run() {
  (
    cd "$TMP" &&
      PLUGIN_CATALOG_ENABLEMENT_MARKETPLACE=".claude-plugin/marketplace.json" \
        PLUGIN_CATALOG_ENABLEMENT_SETTINGS=".claude/settings.json" \
        PLUGIN_CATALOG_ENABLEMENT_BOOTSTRAP=".claude/cloud-bootstrap.sh" \
        PLUGIN_CATALOG_ENABLEMENT_FLEET="${FLEET_OVERRIDE:-$FLEET}" \
        bash "$SUT" 2>&1
  )
}

# Every fixture below declares the "fixture" marketplace unless it overrides
# this, so the identity check agrees by default and each case exercises only
# the drift class it names. The fleet list is empty unless a case says
# otherwise, so the settings file alone has to cover the catalog there.
write_bootstrap fixture
write_fleet

# --- 1. Happy path: catalog and enabledPlugins name the same set. -----------
write_marketplace alpha beta gamma
printf 'alpha true\nbeta true\ngamma true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'none orphaned; keys sorted' <<<"$out"; then
  ok "catalog and enabledPlugins in agreement passes"
else
  fail "happy path should pass (rc=$rc): $out"
fi

# --- 2. The class that shipped: catalogued, enabled nowhere. ----------------
write_marketplace alpha beta gamma
printf 'alpha true\ngamma true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNENABLED PLUGIN' <<<"$out" && grep -q "'beta'" <<<"$out"; then
  ok "a catalogued plugin enabled neither by the fleet list nor by settings fails the gate"
else
  fail "plugin enabled nowhere should fail (rc=$rc): $out"
fi

# --- 2b. The fleet list covers what settings no longer mirrors. -------------
# This is the post-migration shape: settings carries only deltas (here one
# opt-out) and the fleet list enables the rest of the catalog.
write_marketplace alpha beta gamma
write_fleet alpha@fixture beta@fixture gamma@fixture
printf 'beta false\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "a catalog the fleet list enables passes with a deltas-only settings block"
else
  fail "fleet-covered catalog should pass (rc=$rc): $out"
fi

# A fleet entry for another marketplace does not cover this catalog.
write_marketplace alpha beta
write_fleet alpha@fixture beta@other-market
printf 'alpha true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "'beta'" <<<"$out"; then
  ok "a fleet entry under another marketplace does not cover a catalogued plugin"
else
  fail "foreign-marketplace fleet entry must not count as coverage (rc=$rc): $out"
fi

# An unreadable or absent fleet list is fatal, never a pass.
write_marketplace alpha
printf 'alpha true\n' | write_settings
printf 'not json\n' >"$FLEET"
out="$(run)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'not a settings-shaped JSON object' <<<"$out"; then
  ok "a malformed fleet list exits 2"
else
  fail "malformed fleet list should exit 2 (rc=$rc): $out"
fi
write_fleet

# --- 3. An explicit false is a decision, not drift. -------------------------
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
# Suffix stripping must be a literal match, not a pattern. Under the original
# `sed -n "s/@$MARKET\$//p"` the '.' in 'melodic.software' matched any
# character, so 'alpha@melodicXsoftware' was accepted as this marketplace's
# key and the genuine 'alpha@melodic.software' entry went unnoticed -- the
# gate reporting drift that did not exist while missing the shape it exists
# to catch. Raised as informational by the security review on #3235.
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
# catalog -- with this lane green over it. Raised as P2 by the Codex review on
# #3235.
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
