#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ledger-repo.sh" setup-new
