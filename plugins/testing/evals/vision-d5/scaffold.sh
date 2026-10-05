#!/usr/bin/env bash
# Stages one variant's screenshots as screens/ in the workspace.
set -euo pipefail

mkdir -p screens
cp "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ui-defects/crops/9a2aa3d8d1ec/"*.png screens/
