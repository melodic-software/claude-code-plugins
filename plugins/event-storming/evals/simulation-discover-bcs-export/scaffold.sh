#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
board=docs/event-storming/courses-20261118-a7f2/big-picture.md
bash "${here}/../fixtures/scaffold-guard.sh" docs
mkdir -p "$(dirname "${board}")"
cat "${here}/../fixtures/big-picture-board-export.md" >"${board}"
