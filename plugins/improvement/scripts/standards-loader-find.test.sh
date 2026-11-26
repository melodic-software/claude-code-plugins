#!/usr/bin/env bash
# test-scope: plugins/improvement/skills/find/SKILL.md plugins/improvement/scripts/org-standards.sh plugins/improvement/reference/standards-contract.md lib/standards-loader-test-helpers.sh
set -uo pipefail

# shellcheck source=../../../lib/standards-loader-test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/standards-loader-test-helpers.sh"

check_stage improvement skills/find/SKILL.md
finish
