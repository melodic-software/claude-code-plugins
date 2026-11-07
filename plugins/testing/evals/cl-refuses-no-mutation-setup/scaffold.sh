#!/usr/bin/env bash
# The Python shop with its mutation-testing config removed, committed on main, on feat/cleanup.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/cleanup-shop.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main shop shop_tests docs REQUIREMENTS.md .remote.git
shop_files
rm docs/conventions/mutation-testing.yaml
g add -A
g commit -q -m "shop"
ws_origin
g switch -q -c feat/cleanup
