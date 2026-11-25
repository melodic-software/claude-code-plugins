#!/usr/bin/env bash
# test-scope: lib/media-render/* lib/media-render/media_templates/* lib/redact.py
# test-scope: plugins/session-flow/vendor/gitleaks/gitleaks-rules.json
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not found"
  exit 0
fi

export PYTHONPATH="..${PYTHONPATH:+:$PYTHONPATH}"
exec python3 -B -m unittest discover -s . -p 'test_media_*.py' -q
