#!/usr/bin/env bash
exec bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/su-seed.sh" \
  su-readme.md=README.md su-app.py=src/web/app.py su-models.py=src/core/models.py su-test_app.py=tests/test_app.py \
  su-area-api-missing-section.md=.claude/tidy-areas/api.md \
  su-area-docs-prose-merge.md=.claude/tidy-areas/docs-prose.md
