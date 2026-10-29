#!/usr/bin/env bash
# Seeds the converged tarnquill fixture, the plugin arm's starting state for scenario T2.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh" tarnquill converged
