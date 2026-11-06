#!/usr/bin/env bash
# orders-portal on topic/export-report with a clean working tree, so nothing hints at an action.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fabrikam-repo.sh" plain
