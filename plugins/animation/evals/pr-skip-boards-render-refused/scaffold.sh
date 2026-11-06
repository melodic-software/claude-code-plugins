#!/usr/bin/env bash
# A production directory whose boards are complete and pass produce.py boards, not yet approved.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" film
bash "${here}/../fixtures/pr-production.sh"
