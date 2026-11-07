#!/usr/bin/env bash
# A JS suite with tests that cannot fail.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main test
au_copy positive/cant-fail-js.test.js test/cant-fail-js.test.js
au_commit
