#!/usr/bin/env bash
# A Jest test whose only assertion is a snapshot.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main test
au_copy corpus/js-jest/bad/jest-receipt-snapshot.test.ts.fixture test/receipt.test.ts
au_commit
