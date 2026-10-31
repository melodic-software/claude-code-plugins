#!/usr/bin/env bash
# Seeds the workspace root as the checkout-service source tree with no git history, no CI, no tests
# and no telemetry, so nothing measures checkout speed.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/checkout-service"

mkdir -p src
cp "$src/README.md" README.md
cp "$src/src/checkout.js" src/checkout.js
cp "$src/src/pricing.js" src/pricing.js
cp "$src/src/inventory.js" src/inventory.js
