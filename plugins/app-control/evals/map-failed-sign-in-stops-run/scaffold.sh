#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p evidence
cp "$here/fixtures/evidence/report.json" evidence/
printf 'png' >evidence/checkout-signin-01-screenshot.png
printf 'png' >evidence/checkout-signin-02-screenshot.png
