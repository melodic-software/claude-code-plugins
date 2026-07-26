#!/usr/bin/env bash
# Black-box contract test for check-plugin-manifest-presence.sh.
#
# Self-contained and cwd-independent: builds a throwaway
# .claude-plugin/marketplace.json + plugins/ tree, runs the checker against
# it, and asserts on exit code + output. Mutates only its own mktemp dir. The
# SUT resolves its paths relative to its own location, so the fixture tree
# carries a copy of it. A green run on the current repo tree is not
# sufficient evidence the gate works -- these fixtures prove it goes red on
# the two failure classes #1547 named (a manifest removed, and a name/key
# mismatch), plus the paired inverse (orphan) check and a happy-path baseline.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-plugin-manifest-presence.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/scripts" "$TMP/.claude-plugin"
cp "$SUT_SRC" "$TMP/scripts/check-plugin-manifest-presence.sh"
SUT="$TMP/scripts/check-plugin-manifest-presence.sh"
MARKETPLACE="$TMP/.claude-plugin/marketplace.json"

make_plugin() {
  # plugin name, manifest name (defaults to plugin name if omitted)
  local plugin="$1" manifest_name="${2:-$1}"
  mkdir -p "$TMP/plugins/$plugin/.claude-plugin"
  printf '{"name": "%s", "version": "0.1.0", "description": "fixture"}\n' "$manifest_name" \
    >"$TMP/plugins/$plugin/.claude-plugin/plugin.json"
}

write_marketplace() {
  # one "name<TAB>source" pair per line on stdin
  {
    echo '{'
    echo '  "name": "fixture-marketplace",'
    echo '  "owner": {"name": "fixture"},'
    echo '  "plugins": ['
    local first=1 name source
    while IFS=$'\t' read -r name source; do
      [[ -n "$name" ]] || continue
      if ((first)); then first=0; else echo ','; fi
      printf '    {"name": "%s", "source": "%s", "category": "development"}' "$name" "$source"
    done
    echo
    echo '  ]'
    echo '}'
  } >"$MARKETPLACE"
}

run() { (cd "$TMP" && bash "$SUT" 2>&1); }

# --- 1. Happy path: manifests present, names match, no orphans -> green. ----
rm -rf "$TMP/plugins"
make_plugin alpha
make_plugin beta
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\n' | write_marketplace
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'no unregistered plugin directories' <<<"$out"; then
  pass "happy path (manifests present, names match, no orphans) passes"
else
  fail "happy path should pass (rc=$rc): $out"
fi

# --- 2. #1547's own failure class: a manifest directory loses its manifest. -
rm -rf "$TMP/plugins/alpha/.claude-plugin"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'MISSING MANIFEST' <<<"$out" && grep -q "'alpha'" <<<"$out"; then
  pass "a plugin directory losing its .claude-plugin/plugin.json fails the gate"
else
  fail "missing manifest should fail (rc=$rc): $out"
fi
make_plugin alpha # restore for the next case

# --- 3. A whole plugin directory vanishing (not just the manifest). --------
rm -rf "$TMP/plugins/beta"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'MISSING PLUGIN DIRECTORY' <<<"$out" && grep -q "'beta'" <<<"$out"; then
  pass "a catalog entry pointing at a vanished directory fails the gate"
else
  fail "vanished plugin directory should fail (rc=$rc): $out"
fi
make_plugin beta # restore for the next case

# --- 4. Name/key mismatch: manifest exists but declares a different name. --
make_plugin beta "not-beta"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'NAME MISMATCH' <<<"$out" && grep -q "'beta'" <<<"$out" && grep -q 'not-beta' <<<"$out"; then
  pass "a manifest name/catalog key mismatch fails the gate"
else
  fail "name mismatch should fail (rc=$rc): $out"
fi
make_plugin beta # restore ("beta" name again)

# --- 5. Malformed manifest: present but no readable "name" field. ----------
mkdir -p "$TMP/plugins/beta/.claude-plugin"
echo '{"version": "0.1.0"}' >"$TMP/plugins/beta/.claude-plugin/plugin.json"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'MALFORMED MANIFEST' <<<"$out"; then
  pass "a manifest with no name field fails the gate"
else
  fail "manifest without a name field should fail (rc=$rc): $out"
fi
make_plugin beta # restore

# --- 6. Inverse check: a plugin directory the catalog never registered. ----
make_plugin gamma
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNREGISTERED PLUGIN DIRECTORY' <<<"$out" && grep -q 'gamma' <<<"$out"; then
  pass "a plugin directory with no catalog entry fails the gate"
else
  fail "unregistered plugin directory should fail (rc=$rc): $out"
fi
rm -rf "$TMP/plugins/gamma"

# --- 6b. A catalog "source" that escapes the repo root (a ".." segment or an
#     absolute path) must fail loudly rather than be probed or silently
#     skipped -- the path-traversal defense-in-depth the gate applies before
#     ever using catalog data to build a filesystem path.
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\nevil\t../../etc\n' | write_marketplace
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNSAFE CATALOG SOURCE' <<<"$out" && grep -q 'evil' <<<"$out"; then
  pass "a catalog source escaping the repo root fails the gate"
else
  fail "path-escaping catalog source should fail (rc=$rc): $out"
fi
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\n' | write_marketplace # restore

# --- 6c. Equivalent spellings of the SAME registered directory must not be
#     reported as unregistered. A trailing slash, a doubled slash and a "."
#     segment all resolve and glob to one directory, so the forward check
#     accepts them; before canonicalization the inverse check keyed on the
#     raw string and reported the very directory the catalog registers.
printf 'alpha\t./plugins/alpha/\nbeta\tplugins/./beta\n' | write_marketplace
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  pass "trailing-slash and dot-segment spellings of a registered directory stay green"
else
  fail "equivalent source spellings should pass (rc=$rc): $out"
fi
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\n' | write_marketplace # restore

# --- 6d. ...and canonicalization must not launder a traversal: dot segments
#     and doubled slashes wrapped around a ".." still have to reach the
#     out-of-tree guard, never be resolved away into a benign-looking path.
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\nevil\t./plugins/.//../../etc/\n' | write_marketplace
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNSAFE CATALOG SOURCE' <<<"$out" && grep -q 'evil' <<<"$out"; then
  pass "dot segments around a '..' do not launder a path-escaping source"
else
  fail "obfuscated path-escaping source should fail (rc=$rc): $out"
fi
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\n' | write_marketplace # restore

# --- 7. Back to green after every fixture is restored/removed. -------------
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  pass "gate returns to green once every fixture is restored"
else
  fail "restored tree should pass (rc=$rc): $out"
fi

# --- 8. Missing marketplace.json is a hard usage error, not a silent pass. -
rm -f "$MARKETPLACE"
out="$(run)"
rc=$?
if [[ $rc -eq 2 ]]; then
  pass "missing marketplace.json exits 2"
else
  fail "missing marketplace.json should exit 2 (rc=$rc): $out"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
