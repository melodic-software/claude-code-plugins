#!/usr/bin/env bash
# test-scope: plugins/discovery/skills/research/SKILL.md plugins/discovery/scripts/org-standards.sh plugins/discovery/reference/standards-contract.md lib/standards-loader-test-helpers.sh
set -uo pipefail

# shellcheck source=../../../lib/standards-loader-test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/standards-loader-test-helpers.sh"

check_stage discovery skills/research/SKILL.md
finish
