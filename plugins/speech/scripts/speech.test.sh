#!/usr/bin/env bash
# test-scope: plugins/speech/skills/*/SKILL.md plugins/speech/hooks/*.sh plugins/speech/scripts/*.json
# test-scope: plugins/speech/scripts/*.py plugins/speech/prerequisites.json plugins/speech/requirements.txt
# test-scope: plugins/speech/.claude-plugin/plugin.json
# test-scope: plugins/speech/vendor/gitleaks/gitleaks-rules.json
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not found"
  exit 0
fi

if ! python3 -c 'import numpy' 2>/dev/null; then
  if [[ "${SPEECH_REQUIRE_DEPS:-}" == 1 ]]; then
    echo "FAIL: numpy missing and SPEECH_REQUIRE_DEPS=1 (install ../requirements.txt with --require-hashes)" >&2
    exit 1
  fi
  echo "SKIP: narrate timing suite: numpy missing (set SPEECH_REQUIRE_DEPS=1 to fail instead)" >&2
fi

exec python3 -m unittest test_narrate test_narrate_chain test_elevenlabs test_assets test_speech_pydeps -q
