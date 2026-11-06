#!/usr/bin/env bash
# A rotoscope work directory whose measure table passes; review.py has not run.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" work
bash "${here}/../fixtures/ro-workdir.sh"
mkdir -p work/out/full
cat >work/out/full/table-full.md <<'MD'
$ measure.py work --tag full

| k | xor | ssim | paper_err | pass |
|---|---|---|---|---|
| 12 | 0.41% | 0.962 | 1.1 | yes |
| 40 | 0.38% | 0.967 | 0.9 | yes |
| 45 | 0.52% | 0.951 | 4.8 | yes |
| 50 | 0.33% | 0.970 | 1.0 | yes |

4/4 drawings meet the target
MD
