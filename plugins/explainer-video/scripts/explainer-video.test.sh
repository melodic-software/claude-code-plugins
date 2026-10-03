#!/usr/bin/env bash
# Contract tests for pydeps.py and render.py. The check functions and the installer need only the standard
# library and always run. The two real renders need ManimCE, ffmpeg and ffprobe and skip without them, so
# EXPLAINER_VIDEO_REQUIRE_DEPS=1 fails the run instead: run it through the launcher, which puts the installed set
# on the path, e.g. `python3 pydeps.py run -- -m unittest test_render` from this directory.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not found"
  exit 0
fi

exec python3 -B -m unittest test_pydeps test_render -q
