#!/usr/bin/env bash
# Contract test for check-plugin-profiles.sh: green on this checkout, red on a copy whose
# build.yaml names a plugin the catalog lacks. The check's rule cases are the plugin's own suite
# (plugins/plugin-profiles/lib/check.test.mjs); this proves the wrapper passes the exit through.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$SCRIPT_DIR/check-plugin-profiles.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

TMP=""
fixture_tree::build TMP --no-lib --label check-plugin-profiles

# An empty home, so the developer's installed plugins and user profiles stay out of the result.
run() { HOME="$TMP/home" CLAUDE_CONFIG_DIR="$TMP/home/.claude" bash "$SUT" "$@" 2>&1; }

out="$(run)"
status=$?
if [[ $status -eq 0 ]]; then ok "the shipped profiles pass on this checkout"; else fail "expected exit 0 on the checkout, got $status: $out"; fi

mkdir -p "$TMP/.claude-plugin" "$TMP/plugins/plugin-profiles"
cp "$REPO/.claude-plugin/marketplace.json" "$TMP/.claude-plugin/"
cp -R "$REPO/plugins/plugin-profiles/profiles" "$TMP/plugins/plugin-profiles/"
printf '  - nope@melodic-software\n' >>"$TMP/plugins/plugin-profiles/profiles/build.yaml"

out="$(run "$TMP")"
status=$?
if [[ $status -eq 1 ]]; then ok "a build.yaml naming nope@melodic-software exits 1"; else fail "expected exit 1 on the nope fixture, got $status: $out"; fi
if [[ "$out" == *"nope@melodic-software, which is not in the catalog"* ]]; then ok "the failure names the plugin"; else fail "expected the failure to name nope@melodic-software; got: $out"; fi

test_harness::report
