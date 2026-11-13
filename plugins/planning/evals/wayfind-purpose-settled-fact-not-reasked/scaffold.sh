#!/usr/bin/env bash
# Seeds the eval workspace with this arm's invoice-export tracker export (prepare-arm.sh copies the arm's variant to current/), stripping the .txt suffix.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/wayfind-charting/settled-facts/current"
mkdir -p tracker-export
for f in "$src"/*.txt; do
  name="$(basename "$f")"
  cp "$f" "tracker-export/${name%.txt}"
done
