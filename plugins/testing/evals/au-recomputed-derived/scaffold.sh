#!/usr/bin/env bash
# A Vitest test whose expected total is rebuilt with reduce from the call's own items.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main test
au_copy corpus/js-vitest/bad/vitest-order-total-recomputed.test.ts.fixture test/order-total.test.ts
au_commit
