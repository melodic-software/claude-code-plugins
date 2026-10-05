#!/usr/bin/env bash
# Stages one variant's screenshots as screens/ in the workspace.
set -euo pipefail

mkdir -p screens
cp "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ui-defects/crops/7095b8baf345/"*.png screens/
