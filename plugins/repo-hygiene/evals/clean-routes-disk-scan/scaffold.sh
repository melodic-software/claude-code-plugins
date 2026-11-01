#!/usr/bin/env bash
# orders-portal with dist/, .pytest_cache/, __pycache__/ and node_modules/ to reclaim.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fabrikam-repo.sh" scan
