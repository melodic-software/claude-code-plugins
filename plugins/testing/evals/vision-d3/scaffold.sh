#!/usr/bin/env bash
# Stages one variant's screenshots as screens/ in the workspace.
set -euo pipefail

mkdir -p screens
cp "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ui-defects/crops/346995188f91/"*.png screens/
