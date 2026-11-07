#!/usr/bin/env bash
# Seeds the session service's heap snapshot under heap/.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${here}/../fixtures/scaffold-guard.sh" heap
mkdir -p heap
cat "${here}/../../skills/analyze-profile/scripts/fixtures/session-cache.heapsnapshot" >heap/session-cache.heapsnapshot
