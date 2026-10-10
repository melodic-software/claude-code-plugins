#!/usr/bin/env bash
# Smoke test for the demo-video pipeline (test_demo_video.py): a synthetic capture goes through
# build_edl.py, produce.py and qc.py and must pass QC, and planted defects must each fail QC.
# Network-free. Needs numpy and Pillow (../requirements.in pins them, ../requirements.txt hash-locks
# them) plus ffmpeg; skips without them, so DEMO_VIDEO_REQUIRE_DEPS=1 fails the run instead: a lane
# that provisions the pinned requirements sets it, and missing dependencies then read as a broken
# environment, not as passing coverage.
# test-scope: plugins/playwright/skills/demo-video/scripts/* plugins/playwright/skills/demo-video/requirements.txt
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not found"
  exit 0
fi

missing=()
for module in numpy PIL; do
  python3 -c "import $module" 2>/dev/null || missing+=("$module")
done
command -v ffmpeg >/dev/null 2>&1 || missing+=(ffmpeg)
command -v ffprobe >/dev/null 2>&1 || missing+=(ffprobe)

if ((${#missing[@]} > 0)); then
  if [[ "${DEMO_VIDEO_REQUIRE_DEPS:-}" == 1 ]]; then
    echo "FAIL: ${missing[*]} missing and DEMO_VIDEO_REQUIRE_DEPS=1 (install ../requirements.txt with --require-hashes)" >&2
    exit 1
  fi
  echo "SKIP: demo-video smoke test: ${missing[*]} missing (set DEMO_VIDEO_REQUIRE_DEPS=1 to fail instead)" >&2
  exit 0
fi

exec python3 -m unittest test_demo_video -q
