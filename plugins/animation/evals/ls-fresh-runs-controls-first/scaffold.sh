#!/usr/bin/env bash
# A complete 12 s rotoscope work directory (768x576, a trace and a drawing for each of its 96 drawings) and three
# 12 s clips of that size: the source, a blurred near miss and a thin-line film in another style.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" work clips packs out
bash "${here}/../fixtures/ro-workdir.sh"
bash "${here}/../fixtures/ro-complete.sh" 12
clip() {
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -loglevel error -f lavfi -i "color=c=0x$2:s=768x576:d=12:r=24" \
      -vf "drawbox=x='200+mod(floor(t*8)*7,240)':y=180:w=160:h=220:color=0x$3:t=$4${5:+,$5}" -pix_fmt yuv420p "$1"
  else
    printf 'placeholder clip\n' >"$1"
  fi
}
mkdir -p clips
clip clips/ink-short.mp4 efe6d2 14110f fill
clip clips/near-miss.mp4 efe6d2 14110f fill boxblur=3
clip clips/ligne-claire.mp4 ffffff 1a3a8a 4
