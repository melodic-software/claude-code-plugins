#!/usr/bin/env bash
# A rotoscope work directory and three short clips: the source, a near miss and another style.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" work clips packs out
bash "${here}/../fixtures/ro-workdir.sh"
clip() {
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -loglevel error -f lavfi -i "color=c=0xefe6d2:s=96x72:d=1" -r 12 -pix_fmt yuv420p "$1"
  else
    printf 'placeholder clip\n' >"$1"
  fi
}
mkdir -p clips
for c in ink-short near-miss ligne-claire; do clip "clips/${c}.mp4"; done
