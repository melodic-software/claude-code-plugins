#!/usr/bin/env bash
# Stages one variant's screenshots as screens/ in the workspace.
set -euo pipefail

mkdir -p screens
cp "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ui-defects/crops/d0f0ba1f4236/"*.png screens/
