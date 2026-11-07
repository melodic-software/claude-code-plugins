#!/usr/bin/env bash
# The audit tree with its three-finding plan, every finding pending.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fn-repo.sh" plan-pending
