#!/usr/bin/env bash
# JS, Python and C# tests with assertion-free bodies, self-identical comparisons and mock-only oracles.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main Tests test tests
au_copy positive/cant-fail-js.test.js test/cant-fail-js.test.js
au_copy positive/test_cant_fail_py.py tests/test_cant_fail_py.py
au_copy positive/CantFailTests.cs Tests/CantFailTests.cs
au_commit
