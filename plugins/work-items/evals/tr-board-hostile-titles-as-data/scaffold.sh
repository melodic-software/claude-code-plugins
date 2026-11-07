#!/usr/bin/env bash
# A local-markdown tracker with three raw items, two with hostile titles, and #43 blocked by #41.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/work-items-a-repo.sh" board-hostile
