#!/usr/bin/env bash
# Seeds a proving run's evidence: the screenshot holds bytes, the trace it lists is empty.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p evidence
cp "$here/fixtures/evidence/report.json" evidence/
printf 'png-bytes' >evidence/cart-header-01-screenshot.png
: >evidence/cart-header-02-trace.zip
