#!/usr/bin/env bash
# A Playwright config with retries: 2 and a file-level cant-fail-ok: annotation, and one sound spec.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main playwright.config.ts tests
au_copy config/exempt/playwright.config.ts playwright.config.ts
au_copy config/scaffold/smoke.spec.ts tests/smoke.spec.ts
au_commit
