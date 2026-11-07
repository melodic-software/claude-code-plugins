#!/usr/bin/env bash
# Genuinely discriminating JS, Python and C# tests: the scan reports zero findings.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main Tests test tests
au_copy negative/discriminating-js.test.js test/discriminating-js.test.js
au_copy negative/test_discriminating_py.py tests/test_discriminating_py.py
au_copy negative/DiscriminatingTests.cs Tests/DiscriminatingTests.cs
au_commit
