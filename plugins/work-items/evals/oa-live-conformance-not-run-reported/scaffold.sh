#!/usr/bin/env bash
# A consumer repository holding a finished adapter spec for provider tasker.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/work-items-a-repo.sh" adapter-tasker
