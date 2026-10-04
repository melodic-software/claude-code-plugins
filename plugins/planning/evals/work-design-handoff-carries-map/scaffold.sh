#!/usr/bin/env bash
# Seeds the eval workspace with the partner-feed tracker export, stripping the .txt suffix.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/partner-feed"
mkdir -p tracker-export
for f in "$src"/*.txt; do
  name="$(basename "$f")"
  cp "$f" "tracker-export/${name%.txt}"
done
