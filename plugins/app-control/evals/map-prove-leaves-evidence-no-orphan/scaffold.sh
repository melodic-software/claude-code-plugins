#!/usr/bin/env bash
# Seeds a proving run's evidence: the screenshot is on disk, the trace the report lists is not.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p evidence
cp "$here/fixtures/evidence/report.json" evidence/
printf '\x89PNG\r\n\x1a\n\0\0\0\rIHDR' >evidence/cart-header-01-screenshot.png
