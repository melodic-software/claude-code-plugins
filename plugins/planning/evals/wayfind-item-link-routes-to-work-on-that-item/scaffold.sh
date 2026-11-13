#!/usr/bin/env bash
# Seeds the eval workspace with the checkout-redesign tracker export, stripping the .txt suffix.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/wayfind-charting/checkout-map"
mkdir -p tracker-export
for f in "$src"/*.txt; do
  name="$(basename "$f")"
  cp "$f" "tracker-export/${name%.txt}"
done
