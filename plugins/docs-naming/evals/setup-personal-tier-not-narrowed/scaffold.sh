#!/usr/bin/env bash
# A tracked team layer with a released tier, plus an ignored personal layer declaring only its own tier.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fn-repo.sh" setup-personal-tier
