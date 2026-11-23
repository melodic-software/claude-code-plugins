#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" film
bash "${here}/../fixtures/pr-production.sh"
