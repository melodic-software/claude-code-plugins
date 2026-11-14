#!/usr/bin/env bash
# Tests for lib/media-render (ADR 0103). The pure modules always run; the ffmpeg-backed ones skip without ffmpeg and
# ffprobe, and the capture test without Playwright for Python, unless MEDIA_RENDER_REQUIRE_DEPS=1, which fails them.
# test-scope: lib/media-render/* lib/media-render/media_templates/* lib/redact.py
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not found"
  exit 0
fi

# lib/redact.py sits one level up here; in a plugin, media_scan.py's copy sits beside its redact.py copy.
export PYTHONPATH="..${PYTHONPATH:+:$PYTHONPATH}"
exec python3 -B -m unittest discover -s . -p 'test_media_*.py' -q
