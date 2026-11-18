#!/usr/bin/env bash
# test-scope: plugins/explainer-video/skills/*/SKILL.md plugins/explainer-video/skills/*.py plugins/explainer-video/scripts/* plugins/explainer-video/hooks/*.sh plugins/explainer-video/requirements.txt plugins/explainer-video/vendor/gitleaks/*
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not found"
  exit 0
fi

exec python3 -B -m unittest test_explainer_video_pydeps test_explainer_video_render test_explainer_video_narration test_explainer_video_stills -q
