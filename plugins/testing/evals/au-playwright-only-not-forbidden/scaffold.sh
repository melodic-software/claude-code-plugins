#!/usr/bin/env bash
# A Playwright config with no forbidOnly key and one sound spec.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main e2e playwright.config.ts
au_copy config/no-retries/playwright.config.ts playwright.config.ts
au_copy config/scaffold/smoke.spec.ts e2e/smoke.spec.ts
au_commit
