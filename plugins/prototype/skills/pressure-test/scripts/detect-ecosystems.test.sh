#!/usr/bin/env bash
# test-scope: plugins/prototype/skills/pressure-test/SKILL.md
# test-scope: plugins/prototype/scripts/detect-ecosystems.sh plugins/prototype/skills/explore-directions/scripts/detect-ecosystems.sh plugins/prototype/reference/skill-wrappers.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

detect_wrapper_contract "$SCRIPT_DIR" pressure-test explore-directions
