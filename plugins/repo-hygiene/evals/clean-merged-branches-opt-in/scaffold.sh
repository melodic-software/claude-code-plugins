#!/usr/bin/env bash
# orders-portal with feature/order-search and fix/total-rounding merged into origin/main, and an unpushed spike/local-draft.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fabrikam-repo.sh" branches
