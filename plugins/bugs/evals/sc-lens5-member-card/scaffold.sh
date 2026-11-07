#!/usr/bin/env bash
# Seed the one rendering file the scan targets, copied by name from the shared fixtures.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" src
mkdir -p src
cat "${here}/../fixtures/member-card.js" >src/member-card.js
