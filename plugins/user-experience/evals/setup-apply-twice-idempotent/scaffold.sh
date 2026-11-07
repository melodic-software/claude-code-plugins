#!/usr/bin/env bash
# A committed team file that already sets jtbd_school: unset.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ux-team-repo.sh" jtbd-unset
