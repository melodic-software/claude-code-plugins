#!/usr/bin/env bash
# A rotoscope work directory with a passing measure.py table, a review.py table flagging one drawing, and four 1:1 crops.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" work
bash "${here}/../fixtures/ro-workdir.sh"
mkdir -p work/out/full
cat >work/out/full/table-012-050.md <<'MD'
# full d012-d050  target: xor <= 1.2 x floor, ssim >= 0.98, ssim_e >= 0.98

| k | pts | xor % | floor % | xor/floor | replica-only px | source-only px | ssim | ssim_e | paper_err | paper_d R,G,B | pass |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 12 | 1.500 | 0.410 | 0.380 | 1.08 | 310 | 290 | 0.9862 | 0.9841 | 1.10 | +0.40,-0.20,+0.10 | yes |
| 40 | 5.000 | 0.380 | 0.360 | 1.06 | 300 | 284 | 0.9871 | 0.9850 | 0.90 | +0.40,-0.20,+0.10 | yes |
| 45 | 5.625 | 0.520 | 0.450 | 1.16 | 395 | 305 | 0.9824 | 0.9812 | 4.80 | +0.40,-0.20,+0.10 | yes |
| 50 | 6.250 | 0.330 | 0.310 | 1.06 | 280 | 262 | 0.9880 | 0.9858 | 1.00 | +0.40,-0.20,+0.10 | yes |
| mean | | 0.410 | 0.375 | | | | 0.9859 | 0.9840 | 1.95 | +0.40,-0.20,+0.10 | 4/4 |
MD
cat >work/out/full/review-012-050.md <<'MD'
# review full d012-d050

| k | largest | blob | edge px | tile | paper_err | paper_d R,G,B | crop at | flags |
|---|---|---|---|---|---|---|---|---|
| 12 | R 210 sliver | - 0 | 0 | 1.4 | 1.10 | +0.40,-0.20,+0.10 | (180,96) |  |
| 40 | B 180 sliver | - 0 | 0 | 1.1 | 0.90 | +0.40,-0.20,+0.10 | (220,96) |  |
| 45 | R 2310 blob | R 2310 | 0 | 6.2 | 4.80 | +0.40,-0.20,+0.10 | (240,96) | blob |
| 50 | B 150 sliver | - 0 | 0 | 0.9 | 1.00 | +0.40,-0.20,+0.10 | (250,96) |  |
MD
png() { printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' | base64 -d >"$1"; }
mkdir -p work/out/full/crops
for k in 012 040 045 050; do png "work/out/full/crops/d${k}.png"; done
