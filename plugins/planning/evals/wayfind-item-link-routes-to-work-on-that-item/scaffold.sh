#!/usr/bin/env bash
# Seeds the eval workspace with the checkout-redesign tracker export, stripping the .txt suffix.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/wayfind-charting/checkout-map"
mkdir -p tracker-export
for name in map-40.md items-40.md; do
  cp "$src/$name.txt" "tracker-export/$name"
done
