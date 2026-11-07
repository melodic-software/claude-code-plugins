#!/usr/bin/env bash
# A committed team file whose routing.disable entry is a flow mapping on line 5.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ux-team-repo.sh" flow-mapping
