#!/usr/bin/env bash
# The fleet manifest the reach skill reads first: made-up hosts desk-01 and lap-01.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fleet-manifest.sh"
