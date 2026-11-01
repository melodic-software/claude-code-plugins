#!/usr/bin/env bash
# orders-portal with three stashes, aged about 8 months, 4 months and 4 days.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fabrikam-repo.sh" stash
