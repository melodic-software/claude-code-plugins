#!/usr/bin/env bash
# A repository whose contributor branch lowers triage_repro_count to 1.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/work-items-a-repo.sh" config-ref-bad
