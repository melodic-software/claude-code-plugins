#!/usr/bin/env bash
# Runs every pixel-art test suite (test_*.py).
# test-scope: plugins/pixel-art/examples/* plugins/pixel-art/palettes/*
# test-scope: plugins/pixel-art/scripts/test_*.py plugins/pixel-art/scripts/gallery.py
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not found"
  exit 0
fi

exec python3 -m unittest discover -s . -p 'test_*.py' -q
