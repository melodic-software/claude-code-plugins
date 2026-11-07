#!/usr/bin/env bash
# A committed repository with no team file.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ux-team-repo.sh" none
