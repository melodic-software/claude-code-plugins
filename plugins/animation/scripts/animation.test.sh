#!/usr/bin/env bash
# test-scope: plugins/animation/skills/*/SKILL.md plugins/animation/skills/*/scripts/* plugins/animation/hooks/*.sh plugins/animation/scripts/*
# test-scope: plugins/animation/requirements.in plugins/animation/styles/* plugins/animation/.claude-plugin/plugin.json
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not found"
  exit 0
fi

missing=()
for module in numpy cv2; do
  python3 -c "import $module" 2>/dev/null || missing+=("$module")
done

if ((${#missing[@]} > 0)); then
  if [[ "${ANIMATION_REQUIRE_DEPS:-}" == 1 ]]; then
    echo "FAIL: ${missing[*]} missing and ANIMATION_REQUIRE_DEPS=1 (install ../requirements.txt with --require-hashes)" >&2
    exit 1
  fi
  echo "SKIP: numpy/opencv suites: ${missing[*]} missing (set ANIMATION_REQUIRE_DEPS=1 to fail instead)" >&2
fi

exec python3 -m unittest test_produce test_pydeps test_inkstats test_woodcut_marks test_render -q
