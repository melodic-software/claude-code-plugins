#!/usr/bin/env bash
# Seeds the eval workspace with a root AGENTS.md whose convention-home pointer moves the home to
# config/team, and the tracker binding there that remaps the wayfind prefix and the human-gated
# label, stripping the .txt suffix. docs/conventions holds nothing.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/wayfind-charting/label-prefix"
mkdir -p config/team
cp "$src/AGENTS.md.txt" AGENTS.md
cp "$src/work-items.yaml.txt" config/team/work-items.yaml
