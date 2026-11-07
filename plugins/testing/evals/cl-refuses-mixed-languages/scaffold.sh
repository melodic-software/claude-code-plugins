#!/usr/bin/env bash
# The Python shop on main, then feat/cleanup adding a bash harness to shop_tests.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/cleanup-shop.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main shop shop_tests docs REQUIREMENTS.md .remote.git
shop_files
g add -A
g commit -q -m "shop"
ws_origin
g switch -q -c feat/cleanup
shop_bash_test shop_tests/total.test.sh
g add -A
g commit -q -m "bash harness"
