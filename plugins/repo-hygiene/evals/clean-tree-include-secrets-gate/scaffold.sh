#!/usr/bin/env bash
# orders-portal on topic/export-report with a tracked edit, an untracked scratch file, ignored dist/ and node_modules/, and a .env.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fabrikam-repo.sh" tree
