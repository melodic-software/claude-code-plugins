#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" src
mkdir -p src
cat "${here}/../fixtures/member-card.js" >src/member-card.js
