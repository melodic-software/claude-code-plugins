#!/usr/bin/env bash
# Seeds the eval workspace with a tracker binding that remaps the wayfind prefix and the
# human-gated label, stripping the .txt suffix.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/wayfind-charting/label-prefix"
mkdir -p docs/conventions
cp "$src/work-items.yaml.txt" docs/conventions/work-items.yaml
