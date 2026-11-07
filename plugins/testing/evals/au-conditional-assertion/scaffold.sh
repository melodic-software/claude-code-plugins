#!/usr/bin/env bash
# A Vitest test asserting only inside a loop over rows and a Jest test asserting only in a catch.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main test
au_copy corpus/js-vitest/bad/vitest-rows-loop-unchecked.test.ts.fixture test/rows.test.ts
au_copy corpus/js-jest/bad/jest-parse-error-in-catch.test.ts.fixture test/parse.test.ts
au_commit
