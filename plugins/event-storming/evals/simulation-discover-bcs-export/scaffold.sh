#!/usr/bin/env bash
# A completed Big Picture board's items, exported as structured markdown, in the workspace.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" big-picture-board-export.md
cat "${here}/../fixtures/big-picture-board-export.md" >big-picture-board-export.md
