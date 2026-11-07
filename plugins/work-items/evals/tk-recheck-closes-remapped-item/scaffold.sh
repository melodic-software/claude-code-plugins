#!/usr/bin/env bash
# A local-markdown tracker whose binding maps recurring-maintenance to scheduled-upkeep, with two due schedule rows and their marked items.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/work-items-a-repo.sh" track-remap
