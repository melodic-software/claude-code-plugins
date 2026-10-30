#!/usr/bin/env bash
# Seeds the converged tarnquill fixture into the workspace root.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh" tarnquill converged
