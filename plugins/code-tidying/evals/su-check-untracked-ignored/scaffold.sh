#!/usr/bin/env bash
set -euo pipefail
seed="$(dirname "${BASH_SOURCE[0]}")/../fixtures/su-seed.sh"
bash "$seed" \
  su-readme.md=README.md su-app.py=src/web/app.py su-models.py=src/core/models.py su-test_app.py=tests/test_app.py \
  su-gitignore=.gitignore su-area-web.md=.claude/tidy-areas/web.md
# scratch-ui.md matches the .gitignore pattern; jobs.md is neither ignored nor tracked.
bash "$seed" --no-commit \
  su-area-web.md=.claude/tidy-areas/scratch-ui.md \
  su-area-jobs.md=.claude/tidy-areas/jobs.md
