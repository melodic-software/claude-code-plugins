#!/usr/bin/env bash
# A rotoscope work directory with a passing measure table, a review table flagging one drawing, and four 1:1 crops.
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
cat >work/out/full/review-full.md <<'MD'
$ review.py work full

| k | cluster px | blob | edge xor | tone diff | paper | crop | flag |
|---|---|---|---|---|---|---|---|
| 12 | 210 | no | 0.02% | 1.4 | #efe6d2 | crops/d012.png | |
| 40 | 180 | no | 0.01% | 1.1 | #efe6d2 | crops/d040.png | |
| 45 | 2310 | yes | 0.03% | 6.2 | #f1e2c8 | crops/d045.png | blob |
| 50 | 150 | no | 0.01% | 0.9 | #efe6d2 | crops/d050.png | |

1 of 4 drawings flagged
MD
png() { printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' | base64 -d >"$1"; }
mkdir -p work/out/full/crops
for k in 012 040 045 050; do png "work/out/full/crops/d${k}.png"; done
