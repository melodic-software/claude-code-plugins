#!/usr/bin/env bash
# A consumer repository holding a finished redmine adapter spec and a hand-written adapter README.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/work-items-a-repo.sh" adapter-redmine
