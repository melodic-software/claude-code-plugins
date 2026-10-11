#!/usr/bin/env bash
# Contract tests for retro-audio WAV rendering.
# test-scope: plugins/retro-audio/examples/*
# test-scope: plugins/retro-audio/scripts/*.py
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not found"
  exit 0
fi

exec python3 -m unittest test_audio.py -q
