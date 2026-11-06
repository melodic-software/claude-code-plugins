#!/usr/bin/env bash
# Three repositories under repos/, each with caches, build output and node_modules to reclaim.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fabrikam-fleet.sh"
