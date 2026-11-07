#!/usr/bin/env bash
# xUnit tests that only check a constructed value exists and has its own type.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main Widgets.Tests
au_copy corpus/cs-xunit/bad/WidgetConstructedNotNullTests.cs.fixture Widgets.Tests/WidgetConstructedNotNullTests.cs
au_commit
