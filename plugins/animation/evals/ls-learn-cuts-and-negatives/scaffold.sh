#!/usr/bin/env bash
# A rotoscope work directory and controls.py measure's calibration and evaluation summaries.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" work out packs
bash "${here}/../fixtures/ro-workdir.sh"
mkdir -p out/calibration out/evaluation
for c in near+blur near+noise flat-polygons other-ligne-claire; do
  printf '%s\n' '{"film": "'"${c}"'", "note": "inkstats --json summary"}' >"out/calibration/${c}.json"
done
for c in near+stripes near+dry other-ligne-claire-b source replica; do
  printf '%s\n' '{"film": "'"${c}"'", "note": "inkstats --json summary"}' >"out/evaluation/${c}.json"
done
