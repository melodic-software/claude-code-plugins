#!/usr/bin/env bash
# Seed the planted-boundary-defect file sc-planted-bug-dry-run scans.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" src
bash "${here}/../sc-planted-bug-dry-run/scaffold.sh"
