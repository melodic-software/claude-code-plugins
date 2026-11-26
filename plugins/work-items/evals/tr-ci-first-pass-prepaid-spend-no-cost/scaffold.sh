#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "${here}/../fixtures/work-items-a-repo.sh" ci-intake
cp "${here}/issue.json" .lane/scratch/issue.json
