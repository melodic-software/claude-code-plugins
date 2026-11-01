#!/usr/bin/env bash
# The text the prompt names, copied into the workspace.
set -euo pipefail
cp "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pr-body-pricing-cache.md" pr-body-pricing-cache.md
