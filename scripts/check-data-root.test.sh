#!/usr/bin/env bash
# test-scope: docs/conventions/attribution.yaml
# Contract test for CHECK_DATA_ROOT in the spoke-plugin-root, plugin-options-docs,
# changelog-parity and cross-plugin-source-drift checks: each reads the tree the
# variable names, not the one holding the script. scripts/check-affected.sh relies
# on it when the pre-push hook runs a merge-base copy of the scripts against a branch.
#
#   bash scripts/check-data-root.test.sh
#
# Each case runs the real script against a fixture tree. This repository's own
# tree passes all four checks, so a script that ignored the variable would exit
# 0 on the failing fixture.
# test-scope: plugins/*/.claude-plugin/plugin.json plugins/*/README.md
# shellcheck disable=SC2016
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh" || exit 2

tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT

# run_in <root> <command...>: sets RC and OUT (stdout and stderr), from a
# working directory that is neither the script's tree nor <root>.
run_in() {
  local root="$1"
  shift
  RC=0
  OUT="$(cd "$tmp" && CHECK_DATA_ROOT="$root" "$@" 2>&1)" || RC=$?
}

check() {
  local name="$1" cond="$2"
  if eval "$cond"; then ok "$name"; else bad "$name" "rc=$RC out=$OUT"; fi
}

# check-spoke-plugin-root.sh
spoke_bad="$tmp/spoke-bad"
spoke_ok="$tmp/spoke-ok"
mkdir -p "$spoke_bad/plugins/p/skills/s/reference" "$spoke_bad/scripts" "$spoke_ok/scripts"
printf 'Run ${CLAUDE_PLUGIN_ROOT}/skills/s/run.sh\n' >"$spoke_bad/plugins/p/skills/s/reference/a.md"
printf '# no entries\n' >"$spoke_bad/scripts/spoke-plugin-root-baseline.txt"
printf '# no entries\n' >"$spoke_ok/scripts/spoke-plugin-root-baseline.txt"
run_in "$spoke_bad" bash "$SELF_DIR/check-spoke-plugin-root.sh" --check
check "spoke-plugin-root reads the tree CHECK_DATA_ROOT names" \
  '[[ $RC == 1 && $OUT == *"plugins/p/skills/s/reference/a.md"* ]]'
run_in "$spoke_ok" bash "$SELF_DIR/check-spoke-plugin-root.sh" --check
check "spoke-plugin-root passes a clean tree CHECK_DATA_ROOT names" '[[ $RC == 0 ]]'

# sync-plugin-options-docs.py
opts_bad="$tmp/opts-bad"
opts_ok="$tmp/opts-ok"
for root in "$opts_bad" "$opts_ok"; do
  mkdir -p "$root/plugins/p/.claude-plugin"
  printf '# p\n' >"$root/plugins/p/README.md"
done
printf '{"name":"p","userConfig":{"k":{"type":"string","title":"K","description":"A key."}}}\n' \
  >"$opts_bad/plugins/p/.claude-plugin/plugin.json"
printf '{"name":"p"}\n' >"$opts_ok/plugins/p/.claude-plugin/plugin.json"
run_in "$opts_bad" python3 "$SELF_DIR/sync-plugin-options-docs.py" --check
check "plugin-options-docs reads the tree CHECK_DATA_ROOT names" \
  '[[ $RC == 1 && $OUT == *"STALE options docs in 1 plugin(s): p"* ]]'
check "plugin-options-docs --check leaves the named tree's README alone" \
  '[[ "$(cat "$opts_bad/plugins/p/README.md")" == "# p" ]]'
run_in "$opts_ok" python3 "$SELF_DIR/sync-plugin-options-docs.py" --check
check "plugin-options-docs passes a clean tree CHECK_DATA_ROOT names" '[[ $RC == 0 ]]'

# The generated block points at upstream docs instead of restating them (#12700).
opts_gen="$tmp/opts-gen"
mkdir -p "$opts_gen/plugins/p/.claude-plugin"
printf '# p\n' >"$opts_gen/plugins/p/README.md"
printf '{"name":"p","userConfig":{"k":{"type":"string"},"tok":{"type":"string","sensitive":true}}}\n' \
  >"$opts_gen/plugins/p/.claude-plugin/plugin.json"
run_in "$opts_gen" python3 "$SELF_DIR/sync-plugin-options-docs.py"
# shellcheck disable=SC2034 # read inside the check conditions, which run through eval
block="$(cat "$opts_gen/plugins/p/README.md")"
check "plugin-options-docs block restates no upstream fact" \
  '[[ $block != *CLAUDE_PLUGIN_OPTION_* && $block != *--config* && $block != *--values-stdin* && $block != *"settings scopes"* && $block != *"will prompt for"* && $block != *"options dialog"* ]]'
check "plugin-options-docs block, pointers only, carries no as-of date or recheck trigger" \
  '[[ $block == *"### Upstream documentation"* && $block != *"As of"* && $block != *"Recheck trigger"* ]]'
check "plugin-options-docs block keeps a sensitive option off the command line" \
  '[[ $block == *"Never put this plugin'"'"'s \`sensitive\` option(s) (\`tok\`) on a command line"* ]]'
check "plugin-options-docs points a mixed plugin at the install fallback" \
  '[[ $block == *"see [Plugin install]"* ]]'
check "plugin-options-docs block keeps its local decisions and pointers" \
  '[[ $block == *"Do **not** uninstall the plugin to reconfigure it"* && $block == *"#what-an-uninstall-deletes-and-keeps"* && $block == *"#plugin-configure"* && $block == *"#pluginconfigs"* && $block == *"**By hand:**"*"**user** settings"* ]]'

opts_sens="$tmp/opts-sens"
mkdir -p "$opts_sens/plugins/p/.claude-plugin"
printf '# p\n' >"$opts_sens/plugins/p/README.md"
printf '{"name":"p","userConfig":{"tok":{"type":"string","sensitive":true}}}\n' \
  >"$opts_sens/plugins/p/.claude-plugin/plugin.json"
run_in "$opts_sens" python3 "$SELF_DIR/sync-plugin-options-docs.py"
# shellcheck disable=SC2034 # read inside the check condition, which runs through eval
block="$(cat "$opts_sens/plugins/p/README.md")"
check "plugin-options-docs withholds the install fallback when every option is sensitive" \
  '[[ $block != *"see [Plugin install]"* && $block == *"the install fallback for a release without \`plugin configure\` does not apply"* ]]'
check "plugin-options-docs offers no by-hand route when every option is sensitive" \
  '[[ $block != *"**By hand:**"* ]]'

# check-changelog-parity.sh
parity_bad="$tmp/parity-bad"
parity_ok="$tmp/parity-ok"
for root in "$parity_bad" "$parity_ok"; do
  mkdir -p "$root/plugins/p/.claude-plugin"
  printf '{"name":"p","version":"1.0.0"}\n' >"$root/plugins/p/.claude-plugin/plugin.json"
done
printf '# Changelog\n\n## [1.0.0]\n\n- First release.\n' >"$parity_ok/plugins/p/CHANGELOG.md"
run_in "$parity_bad" bash "$SELF_DIR/check-changelog-parity.sh" --check
check "changelog-parity reads the tree CHECK_DATA_ROOT names" \
  '[[ $RC == 1 && $OUT == *"plugins/p/CHANGELOG.md"* ]]'
run_in "$parity_ok" bash "$SELF_DIR/check-changelog-parity.sh" --check
check "changelog-parity passes a clean tree CHECK_DATA_ROOT names" '[[ $RC == 0 ]]'
RC=0
OUT="$(cd "$tmp" && CHECK_DATA_ROOT="$parity_bad" CHANGELOG_PARITY_ROOT="$parity_ok" bash "$SELF_DIR/check-changelog-parity.sh" --check 2>&1)" || RC=$?
check "changelog-parity still prefers CHANGELOG_PARITY_ROOT when both are set" '[[ $RC == 0 ]]'

# check-cross-plugin-source-drift.sh
drift_bad="$tmp/drift-bad"
drift_ok="$tmp/drift-ok"
for root in "$drift_bad" "$drift_ok"; do
  mkdir -p "$root/plugins/a/reference" "$root/plugins/b/reference" "$root/scripts"
  printf 'same\n' >"$root/plugins/a/reference/shared.md"
  printf 'same\n' >"$root/plugins/b/reference/shared.md"
done
printf '# no entries\n' >"$drift_bad/scripts/cross-plugin-source-registry.txt"
printf 'reference/shared.md\n' >"$drift_ok/scripts/cross-plugin-source-registry.txt"
run_in "$drift_bad" bash "$SELF_DIR/check-cross-plugin-source-drift.sh" --check
check "cross-plugin-source-drift reads the tree CHECK_DATA_ROOT names" \
  '[[ $RC == 1 && $OUT == *"UNREGISTERED: reference/shared.md"* ]]'
run_in "$drift_ok" bash "$SELF_DIR/check-cross-plugin-source-drift.sh" --check
check "cross-plugin-source-drift passes a clean tree CHECK_DATA_ROOT names" '[[ $RC == 0 ]]'

test_harness::report
