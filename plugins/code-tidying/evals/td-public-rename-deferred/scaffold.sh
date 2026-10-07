#!/usr/bin/env bash
# Seeds a shell library sourced by other repositories and a caller script, then switches to a feature branch.
set -euo pipefail

seed="$(dirname "${BASH_SOURCE[0]}")/../fixtures/td-seed.sh"
bash "$seed" td-text.sh=scripts/lib/text.sh td-deploy.sh=scripts/deploy.sh
git checkout -q -b feature/deploy-stamp
