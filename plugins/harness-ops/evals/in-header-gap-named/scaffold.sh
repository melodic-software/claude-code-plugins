#!/usr/bin/env bash
set -euo pipefail
cp "$(dirname "${BASH_SOURCE[0]}")/../fixtures/in-header-gap-inventory.json" claude-inventory.json
