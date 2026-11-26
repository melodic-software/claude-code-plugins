#!/usr/bin/env bash
# test-scope: plugins/planning/skills/interview/SKILL.md plugins/planning/skills/interview/context/loop.md plugins/planning/scripts/org-standards.sh plugins/planning/reference/standards-contract.md lib/standards-loader-test-helpers.sh
set -uo pipefail

# shellcheck source=../../../lib/standards-loader-test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/standards-loader-test-helpers.sh"

assert_eq "planning/skills/interview: SKILL.md sends an engineering session to the loop spoke's engineering defaults" 1 \
  "$(grep -cF "[\`context/loop.md\`](context/loop.md) \"Engineering defaults\"" "$SCRIPT_DIR/../plugins/planning/skills/interview/SKILL.md")"
check_stage planning skills/interview/context/loop.md
finish
