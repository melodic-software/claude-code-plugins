#!/usr/bin/env bash
# Skill-local entry point for the plugin's shared ecosystem detector.
#
# Why this wrapper exists: an `allowed-tools` Bash rule can only substitute
# ${CLAUDE_SKILL_DIR} and ${CLAUDE_PROJECT_DIR} (${CLAUDE_PLUGIN_ROOT} stays a
# literal string there and the grant goes inert), so a grant that must reach a
# bundled script has to name a path under the skill's own directory. The
# detector itself is shared with the sibling explore-directions skill and stays
# single-sourced at the plugin root; this file is the ${CLAUDE_SKILL_DIR}-
# addressable handle for it.
#
# Self-locating rather than ${CLAUDE_PLUGIN_ROOT}-resolving: that variable is
# not exported into the Bash tool's environment, so a shell expansion of it
# inside a script yields an empty string.
set -euo pipefail

exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/scripts/detect-ecosystems.sh" "$@"
