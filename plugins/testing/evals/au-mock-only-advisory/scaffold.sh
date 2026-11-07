#!/usr/bin/env bash
# A mock-only interaction test beside an annotated deliberate case.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main test
au_copy mock-only/mock-only-js.test.js test/publish.test.js
au_copy exempt/exempted-js.test.js test/boot.test.js
au_commit
