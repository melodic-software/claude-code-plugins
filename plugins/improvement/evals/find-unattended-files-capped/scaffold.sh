#!/usr/bin/env bash
# Seeds the workspace root as the checkout-service source tree, with nothing that measures speed,
# so the top candidate is the instrument-checkout item the prompt's open item #41 already tracks.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"
