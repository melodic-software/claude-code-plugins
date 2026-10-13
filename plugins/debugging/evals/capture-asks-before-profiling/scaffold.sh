#!/usr/bin/env bash
# Seeds the checkout-app tree, which carries workers/export.js.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh"
