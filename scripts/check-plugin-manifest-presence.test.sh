#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-plugin-manifest-presence.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

TMP=""

fixture_tree::build TMP --sut "$SUT_SRC"
mkdir -p "$TMP/.claude-plugin"
SUT="$TMP/scripts/check-plugin-manifest-presence.sh"
MARKETPLACE="$TMP/.claude-plugin/marketplace.json"

make_plugin() {
  local plugin="$1" manifest_name="${2:-$1}"
  mkdir -p "$TMP/plugins/$plugin/.claude-plugin"
  printf '{"name": "%s", "version": "0.1.0", "description": "fixture"}\n' "$manifest_name" \
    >"$TMP/plugins/$plugin/.claude-plugin/plugin.json"
}

write_marketplace() {
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

rm -rf "$TMP/plugins"
make_plugin alpha
make_plugin beta
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\n' | write_marketplace
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'no unregistered plugin directories' <<<"$out"; then
  ok "happy path (manifests present, names match, no orphans) passes"
else
  fail "happy path should pass (rc=$rc): $out"
fi

rm -rf "$TMP/plugins/alpha/.claude-plugin"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'MISSING MANIFEST' <<<"$out" && grep -q "'alpha'" <<<"$out"; then
  ok "a plugin directory losing its .claude-plugin/plugin.json fails the gate"
else
  fail "missing manifest should fail (rc=$rc): $out"
fi
make_plugin alpha

rm -rf "$TMP/plugins/beta"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'MISSING PLUGIN DIRECTORY' <<<"$out" && grep -q "'beta'" <<<"$out"; then
  ok "a catalog entry pointing at a vanished directory fails the gate"
else
  fail "vanished plugin directory should fail (rc=$rc): $out"
fi
make_plugin beta

make_plugin beta "not-beta"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'NAME MISMATCH' <<<"$out" && grep -q "'beta'" <<<"$out" && grep -q 'not-beta' <<<"$out"; then
  ok "a manifest name/catalog key mismatch fails the gate"
else
  fail "name mismatch should fail (rc=$rc): $out"
fi
make_plugin beta

mkdir -p "$TMP/plugins/beta/.claude-plugin"
echo '{"version": "0.1.0"}' >"$TMP/plugins/beta/.claude-plugin/plugin.json"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'MALFORMED MANIFEST' <<<"$out"; then
  ok "a manifest with no name field fails the gate"
else
  fail "manifest without a name field should fail (rc=$rc): $out"
fi
make_plugin beta

make_plugin gamma
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNREGISTERED PLUGIN DIRECTORY' <<<"$out" && grep -q 'gamma' <<<"$out"; then
  ok "a plugin directory with no catalog entry fails the gate"
else
  fail "unregistered plugin directory should fail (rc=$rc): $out"
fi
rm -rf "$TMP/plugins/gamma"

printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\nevil\t../../etc\n' | write_marketplace
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNSAFE CATALOG SOURCE' <<<"$out" && grep -q 'evil' <<<"$out"; then
  ok "a catalog source escaping the repo root fails the gate"
else
  fail "path-escaping catalog source should fail (rc=$rc): $out"
fi
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\n' | write_marketplace

OUTSIDE="$(mktemp -d)"
mkdir -p "$OUTSIDE/.claude-plugin"
printf '{"name":"evil"}\n' >"$OUTSIDE/.claude-plugin/plugin.json"
for src in "$OUTSIDE" 'C:/outside'; do
  printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\nevil\t%s\n' "$src" | write_marketplace
  out="$(run)"
  rc=$?
  if [[ $rc -eq 1 ]] && grep -q 'UNSAFE CATALOG SOURCE' <<<"$out" && grep -q 'evil' <<<"$out"; then
    ok "an absolute catalog source ($src) fails the gate without being probed"
  else
    fail "absolute catalog source $src should fail as unsafe (rc=$rc): $out"
  fi
done
rm -rf "$OUTSIDE"
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\n' | write_marketplace

printf 'alpha\t./plugins/alpha/\nbeta\tplugins/./beta\n' | write_marketplace
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "trailing-slash and dot-segment spellings of a registered directory stay green"
else
  fail "equivalent source spellings should pass (rc=$rc): $out"
fi
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\n' | write_marketplace

printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\nevil\t./plugins/.//../../etc/\n' | write_marketplace
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'UNSAFE CATALOG SOURCE' <<<"$out" && grep -q 'evil' <<<"$out"; then
  ok "dot segments around a '..' do not launder a path-escaping source"
else
  fail "obfuscated path-escaping source should fail (rc=$rc): $out"
fi
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\n' | write_marketplace

mkdir -p "$TMP/plugins/alpha/bin"
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "an empty top-level bin/ directory passes"
else
  fail "empty bin/ should pass (rc=$rc): $out"
fi
printf '#!/usr/bin/env bash\n' >"$TMP/plugins/alpha/bin/tool"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'TOP-LEVEL BIN DIRECTORY' <<<"$out" && grep -q 'plugins/alpha/bin' <<<"$out"; then
  ok "a plugin with a populated top-level bin/ fails the gate"
else
  fail "populated bin/ should fail (rc=$rc): $out"
fi
rm -rf "$TMP/plugins/alpha/bin"
mkdir -p "$TMP/plugins/alpha/scripts/bin"
printf 'x\n' >"$TMP/plugins/alpha/scripts/bin/tool"
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "a bin/ below the plugin root does not trip the gate"
else
  fail "nested bin/ should pass (rc=$rc): $out"
fi
rm -rf "$TMP/plugins/alpha/scripts"

make_plugin external-agents
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\nexternal-agents\t./plugins/external-agents\n' | write_marketplace
mkdir -p "$TMP/plugins/external-agents/bin"
printf '#!/usr/bin/env node\n' >"$TMP/plugins/external-agents/bin/external-agents"
out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "external-agents' populated top-level bin/ passes (the one exemption)"
else
  fail "external-agents bin/ should pass (rc=$rc): $out"
fi
mkdir -p "$TMP/plugins/beta/bin"
printf 'x\n' >"$TMP/plugins/beta/bin/tool"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'plugins/beta/bin' <<<"$out" && ! grep -q 'plugins/external-agents/bin' <<<"$out"; then
  ok "the exemption names one plugin: another plugin's bin/ still fails"
else
  fail "beta bin/ should fail and external-agents should not be named (rc=$rc): $out"
fi
rm -rf "$TMP/plugins/beta/bin"
printf 'x\n' >"$TMP/plugins/external-agents/bin/extra"
out="$(run)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'plugins/external-agents/bin' <<<"$out"; then
  ok "the exemption covers one file: anything else in external-agents' bin/ fails"
else
  fail "an extra file in external-agents bin/ should fail (rc=$rc): $out"
fi
rm -rf "$TMP/plugins/external-agents"
printf 'alpha\t./plugins/alpha\nbeta\t./plugins/beta\n' | write_marketplace

out="$(run)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "gate returns to green once every fixture is restored"
else
  fail "restored tree should pass (rc=$rc): $out"
fi

rm -f "$MARKETPLACE"
out="$(run)"
rc=$?
if [[ $rc -eq 2 ]]; then
  ok "missing marketplace.json exits 2"
else
  fail "missing marketplace.json should exit 2 (rc=$rc): $out"
fi

test_harness::report
