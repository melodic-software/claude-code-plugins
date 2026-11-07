#!/usr/bin/env bash
# A local-markdown tracker with categorized items, one of them claimed, and one overdue schedule row.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/work-items-a-repo.sh" track-stats
