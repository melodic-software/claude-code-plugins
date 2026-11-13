#!/usr/bin/env bash
# Seeds the eval workspace with this arm's invoice-export tracker export (prepare-arm.sh copies the arm's variant to current/), stripping the .txt suffix.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/wayfind-charting/settled-facts/current"
mkdir -p tracker-export
for name in map-700.md items-700.md; do
  cp "$src/$name.txt" "tracker-export/$name"
done
