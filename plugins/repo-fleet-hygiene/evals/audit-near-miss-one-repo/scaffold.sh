#!/usr/bin/env bash
# One made-up checkout in the case cwd with a merged branch, an unmerged one, and ignored caches.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fleet-repos.sh" single
