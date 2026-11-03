#!/usr/bin/env bash
# The text the prompt names, copied into the workspace.
set -euo pipefail
cp "$(dirname "${BASH_SOURCE[0]}")/../fixtures/agent-instruction-excerpt.md" agent-instruction-excerpt.md
