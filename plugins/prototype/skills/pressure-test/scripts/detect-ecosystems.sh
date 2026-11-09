#!/usr/bin/env bash
# Skill-local entry point for the plugin's shared ecosystem detector.
#
# This plugin's `allowed-tools` Bash grants name a path under
# ${CLAUDE_SKILL_DIR}, never under ${CLAUDE_PLUGIN_ROOT}, so the grant needs
# this path under the skill's own directory. That is a repo convention; its
# reason is the header paragraph of
# plugins/prototype/scripts/allowed-tools-pairing.test.sh that opens "This gate
# requires `${CLAUDE_SKILL_DIR}` in a grant". The detector is shared with the
# sibling explore-directions skill and stays single-sourced at the plugin root.
#
# Self-locating rather than ${CLAUDE_PLUGIN_ROOT}-resolving: that variable is
# not exported into the Bash tool's environment, so a shell expansion of it
# inside a script yields an empty string.
set -euo pipefail

exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/detect-ecosystems.sh" "$@"
