#!/usr/bin/env bash
# Seeds the checkout-app tree and the staging CPU profile.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh"
