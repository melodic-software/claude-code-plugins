#!/usr/bin/env bash
# Seeds the eval workspace with a tracker binding that remaps the wayfind prefix and the
# human-gated label, and a tracker export whose map uses them, stripping the .txt suffix.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/wayfind-charting/label-prefix"
mkdir -p docs/conventions tracker-export
cp "$src/work-items.yaml.txt" docs/conventions/work-items.yaml
for name in map-60.md items-60.md; do
  cp "$src/$name.txt" "tracker-export/$name"
done
