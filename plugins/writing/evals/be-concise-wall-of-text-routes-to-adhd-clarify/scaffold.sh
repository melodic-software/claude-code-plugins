#!/usr/bin/env bash
# The text the prompt names, copied into the workspace.
set -euo pipefail
cp "$(dirname "${BASH_SOURCE[0]}")/../fixtures/wall-of-text-migration-decisions.md" wall-of-text-migration-decisions.md
