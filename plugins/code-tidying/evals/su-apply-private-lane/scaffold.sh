#!/usr/bin/env bash
set -euo pipefail
seed="$(dirname "${BASH_SOURCE[0]}")/../fixtures/su-seed.sh"
bash "$seed" \
  su-readme.md=README.md su-app.py=src/web/app.py su-models.py=src/core/models.py su-test_app.py=tests/test_app.py
# A developer's lane under a name the team does not track: present, complete, never committed.
bash "$seed" --no-commit su-lane-mine.md=.claude/tidy-lanes/mine.md
