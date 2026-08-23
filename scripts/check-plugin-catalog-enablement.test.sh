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

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/scripts" "$TMP/.claude-plugin" "$TMP/.claude"
cp "$SUT_SRC" "$TMP/scripts/check-plugin-catalog-enablement.sh"
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

run() {
  (
    cd "$TMP" &&
      PLUGIN_CATALOG_ENABLEMENT_MARKETPLACE=".claude-plugin/marketplace.json" \
        PLUGIN_CATALOG_ENABLEMENT_SETTINGS=".claude/settings.json" \
        bash "$SUT" 2>&1
  )
}

# --- 1. Happy path: catalog and enabledPlugins name the same set. -----------
write_marketplace alpha beta gamma
printf 'alpha true\nbeta true\ngamma true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'none orphaned; keys sorted' <<<"$out"; then
  pass "catalog and enabledPlugins in agreement passes"
else
  fail "happy path should pass (rc=$rc): $out"
fi

# --- 2. The class that shipped: catalogued, never enabled. ------------------
write_marketplace alpha beta gamma
printf 'alpha true\ngamma true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNENABLED PLUGIN' <<<"$out" && grep -q "'beta'" <<<"$out"; then
  pass "a catalogued plugin with no enabledPlugins key fails the gate"
else
  fail "missing enabledPlugins key should fail (rc=$rc): $out"
fi

# --- 3. An explicit false is a decision, not drift. -------------------------
write_marketplace alpha beta gamma
printf 'alpha true\nbeta false\ngamma true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  pass "a plugin explicitly disabled (false) still passes"
else
  fail "an explicit false should pass (rc=$rc): $out"
fi

# --- 4. Inverse: an enabled id the catalog no longer carries. ---------------
write_marketplace alpha gamma
printf 'alpha true\nbeta true\ngamma true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'ORPHANED ENABLED ENTRY' <<<"$out" && grep -q "'beta@fixture'" <<<"$out"; then
  pass "an enabledPlugins id with no catalog entry fails the gate"
else
  fail "orphaned enabled entry should fail (rc=$rc): $out"
fi

# --- 5. Keys out of byte order. ---------------------------------------------
write_marketplace alpha beta gamma
printf 'gamma true\nalpha true\nbeta true\n' | write_settings
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNSORTED enabledPlugins' <<<"$out"; then
  pass "enabledPlugins keys out of byte order fail the gate"
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
  pass "an enabledPlugins key for a different marketplace is ignored"
else
  fail "foreign-marketplace key should not fail the gate (rc=$rc): $out"
fi

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
  pass "two declared marketplaces is fatal rather than a guess"
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
  pass "invalid settings JSON exits 2"
else
  fail "invalid settings JSON should exit 2 (rc=$rc): $out"
fi

write_marketplace alpha
printf 'alpha true\n' | write_settings
rm -f "$MARKETPLACE"
out="$(run)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'not found' <<<"$out"; then
  pass "a missing marketplace.json exits 2"
else
  fail "missing marketplace.json should exit 2 (rc=$rc): $out"
fi

if ((fails > 0)); then
  printf '\n%d check(s) failed.\n' "$fails" >&2
  exit 1
fi
echo
echo "All check-plugin-catalog-enablement.sh contract checks passed."
