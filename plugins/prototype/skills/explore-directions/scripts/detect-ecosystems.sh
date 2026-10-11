#!/usr/bin/env bash
# Skill-local entry point for the plugin's shared ecosystem detector.
#
# Why this wrapper exists: this plugin's `allowed-tools` Bash grants name a
# path under ${CLAUDE_SKILL_DIR}, never under ${CLAUDE_PLUGIN_ROOT}, so a grant
# that must reach a bundled script needs a path under the skill's own
# directory. That is a repo convention, not a platform limit; its reason is
# kept in the header paragraph of
# plugins/prototype/scripts/allowed-tools-pairing.test.sh that opens "This gate requires
# `${CLAUDE_SKILL_DIR}` in a grant" (lines 14-24; as of 2026-10-11; recheck
# when that paragraph moves or is reworded, or the gate stops requiring
# ${CLAUDE_SKILL_DIR} in a grant). Which
# variables an `allowed-tools` Bash rule substitutes is read live from
# https://code.claude.com/docs/en/skills#available-string-substitutions
# (as of 2026-10-11; recheck when that section changes which variables a
# plugin skill's `allowed-tools` rules substitute). The
# detector itself is shared with the sibling pressure-test skill and stays
# single-sourced at the plugin root; this file is the ${CLAUDE_SKILL_DIR}-
# addressable handle for it.
#
# Self-locating rather than ${CLAUDE_PLUGIN_ROOT}-resolving: that variable is
# not exported into the Bash tool's environment, so a shell expansion of it
# inside a script yields an empty string.
set -euo pipefail

exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/detect-ecosystems.sh" "$@"
