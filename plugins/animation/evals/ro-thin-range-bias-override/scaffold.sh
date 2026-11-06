#!/usr/bin/env bash
# A rotoscope work directory with 60 indexed drawings and one override.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" work
bash "${here}/../fixtures/ro-workdir.sh"
