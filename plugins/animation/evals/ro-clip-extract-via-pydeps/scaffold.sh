#!/usr/bin/env bash
# A one-second reference clip; the work dir roto/ink-short does not exist yet.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" clips roto
clip() {
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -loglevel error -f lavfi -i "color=c=0xefe6d2:s=96x72:d=1" -r 12 -pix_fmt yuv420p "$1"
  else
    printf 'placeholder clip\n' >"$1"
  fi
}
mkdir -p clips
clip clips/ink-short.mp4
