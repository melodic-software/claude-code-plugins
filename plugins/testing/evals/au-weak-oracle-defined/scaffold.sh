#!/usr/bin/env bash
# A Jest test whose only oracle is toBeDefined on a database row.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main test
au_copy corpus/js-jest/bad/jest-create-user-defined-verbatim.test.ts.fixture test/create-user.test.ts
au_commit
