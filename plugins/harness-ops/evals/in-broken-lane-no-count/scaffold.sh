#!/usr/bin/env bash
# A saved inventory whose builtin_commands lane is degraded and whose bundled_skills lane is broken.
set -euo pipefail
cp "$(dirname "${BASH_SOURCE[0]}")/../fixtures/in-claude-inventory.json" claude-inventory.json
