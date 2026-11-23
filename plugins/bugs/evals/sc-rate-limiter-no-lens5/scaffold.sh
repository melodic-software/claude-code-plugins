#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" src
mkdir -p src
cat "${here}/../fixtures/rate-limiter.js" >src/rate-limiter.js
