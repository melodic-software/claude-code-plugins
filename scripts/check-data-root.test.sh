#!/usr/bin/env bash
# Contract test for CHECK_DATA_ROOT in the spoke-plugin-root, plugin-options-docs
# and changelog-parity checks: each reads the tree the variable names, not the
# one holding the script. scripts/check-affected.sh relies on it when the
# pre-push hook runs a merge-base copy of the scripts against a branch.
#
#   bash scripts/check-data-root.test.sh
#
# Each case runs the real script against a fixture tree. This repository's own
# tree passes all three checks, so a script that ignored the variable would exit
# 0 on the failing fixture.
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

test_harness::report
