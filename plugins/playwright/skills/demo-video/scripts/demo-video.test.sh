#!/usr/bin/env bash
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
