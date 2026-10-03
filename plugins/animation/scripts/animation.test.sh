#!/usr/bin/env bash
# Contract tests for the animation scripts produce.py, pydeps.py, inkstats.py and woodcut_marks.py.
# test_produce and test_pydeps need only the standard library and always run (test_pydeps skips without
# pip). test_inkstats and test_woodcut_marks need numpy and opencv (../requirements.in pins them,
# ../requirements.txt hash-locks them) and skip without them, so ANIMATION_REQUIRE_DEPS=1 fails the run
# instead: a lane that provisions the pinned requirements sets it, and missing dependencies then read as a
# broken environment, not as passing coverage.
# test-scope: plugins/animation/skills/*/SKILL.md plugins/animation/skills/*/scripts/* plugins/animation/hooks/*.sh
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

exec python3 -m unittest test_produce test_pydeps test_inkstats test_woodcut_marks -q
