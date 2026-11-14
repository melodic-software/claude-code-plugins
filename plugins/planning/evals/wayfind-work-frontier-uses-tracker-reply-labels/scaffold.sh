#!/usr/bin/env bash
# Seeds the eval workspace with a tracker export whose map uses the remapped wayfind prefix and
# human-gated label, stripping the .txt suffix. No binding file: the labels come from the
# /work-items:track wayfind-labels reply the prompt supplies.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/wayfind-charting/label-prefix"
mkdir -p tracker-export
for name in map-60.md items-60.md; do
  cp "$src/$name.txt" "tracker-export/$name"
done
