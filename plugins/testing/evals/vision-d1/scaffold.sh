#!/usr/bin/env bash
# Stages one variant's screenshots as screens/ in the workspace.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/ui-defects/crops/a225d73f29a0/"
mkdir -p screens
cp "${src}375-load.png" "${src}375-after-1s.png" "${src}1280-load.png" "${src}1280-after-1s.png" screens/
