#!/usr/bin/env bash
# origin/main sets triage_repro_count: 3; the checked-out branch sets 1.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/work-items-a-repo.sh" config-ref-pinned
