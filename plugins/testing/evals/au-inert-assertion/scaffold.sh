#!/usr/bin/env bash
# An unawaited Playwright web-first matcher and a pytest tuple assert.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main e2e tests
au_copy corpus/js-playwright/bad/playwright-saved-unawaited.spec.ts.fixture e2e/saved.spec.ts
au_copy corpus/py-pytest/bad/test_pytest_total_tuple_assert.py.fixture tests/test_total.py
au_commit
