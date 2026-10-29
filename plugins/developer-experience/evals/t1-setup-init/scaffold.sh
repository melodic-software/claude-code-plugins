#!/usr/bin/env bash
# Seeds the bare tarnquill fixture, the starting state for scenario T1 in every arm.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh" tarnquill bare
