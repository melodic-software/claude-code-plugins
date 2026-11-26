#!/usr/bin/env bash
# test-scope: plugins/review/skills/code-review/SKILL.md plugins/review/scripts/org-standards.sh plugins/review/reference/standards-contract.md lib/standards-loader-test-helpers.sh
set -uo pipefail

# shellcheck source=../../../lib/standards-loader-test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/standards-loader-test-helpers.sh"

check_stage review skills/code-review/SKILL.md
finish
