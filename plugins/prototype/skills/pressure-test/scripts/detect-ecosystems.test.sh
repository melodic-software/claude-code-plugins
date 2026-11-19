#!/usr/bin/env bash
# Contract tests for this skill's detect-ecosystems.sh WRAPPER.
#
# The wrapper is not a second detector. It is the ${CLAUDE_SKILL_DIR}-addressable
# handle for the one at plugins/prototype/scripts/detect-ecosystems.sh, and it
# exists only because an `allowed-tools` Bash rule can substitute
# ${CLAUDE_SKILL_DIR} but leaves ${CLAUDE_PLUGIN_ROOT} a literal string, which
# makes any grant naming the plugin root inert. So the grant has to name a path
# under the skill's own directory, and this file is that path.
#
# Two ways that arrangement degrades, both of which look harmless in review:
#
#   1. Someone "removes the indirection" by pasting the detector's body in here.
#      The skill keeps working, and the two copies then drift apart silently.
#      The single-source assertions below fail that edit.
#   2. Someone tidies the header comment away, or swaps the self-locating
#      dirname walk for a ${CLAUDE_PLUGIN_ROOT} expansion, which is empty in the
#      Bash tool's environment. The grant goes inert and the preamble prints
#      nothing. The rationale and resolution assertions below fail that edit.
#
# The detector's own behavior is covered by its sibling suite at the plugin
# root; this suite proves delegation, not detection, plus one end-to-end smoke
# check that the delegation actually reaches a working detector.
#
# test-scope: plugins/prototype/skills/pressure-test/SKILL.md
# test-scope: plugins/prototype/scripts/detect-ecosystems.sh plugins/prototype/skills/explore-directions/scripts/detect-ecosystems.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

detect_wrapper_contract "$SCRIPT_DIR" pressure-test explore-directions
