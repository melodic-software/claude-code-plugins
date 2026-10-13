#!/usr/bin/env bash
# Seeds the checkout-app tree and the production heap snapshot at heap/api.heapsnapshot.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh"
