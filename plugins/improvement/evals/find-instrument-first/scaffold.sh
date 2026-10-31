#!/usr/bin/env bash
# Seeds the workspace root as the checkout-service source tree, with nothing that measures speed.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"
