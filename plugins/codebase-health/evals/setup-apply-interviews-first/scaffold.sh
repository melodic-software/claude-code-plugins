#!/usr/bin/env bash
# Fabrikam ledger-api in its own repository, with a second package under packages/ and a current and an archived docs page.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ledger-repo.sh" setup-ambiguous
