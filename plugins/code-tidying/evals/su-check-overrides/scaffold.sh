#!/usr/bin/env bash
set -euo pipefail
seed="$(dirname "${BASH_SOURCE[0]}")/../fixtures/su-seed.sh"
bash "$seed" \
  su-readme.md=README.md su-app.py=src/web/app.py su-models.py=src/core/models.py su-test_app.py=tests/test_app.py \
  su-claude.md=CLAUDE.md su-ruff.toml=ruff.toml su-editorconfig-root=.editorconfig
bash "$seed" --no-commit su-overrides.md=.claude/code-tidying/exclusion-overrides.md
