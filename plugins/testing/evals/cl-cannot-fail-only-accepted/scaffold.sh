#!/usr/bin/env bash
# The C# shop committed on main with verification: standard, on feat/cleanup, with no
# mutation-testing config.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/cleanup-dotnet.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main Shop Shop.Tests .remote.git
dotnet_files
mkdir -p docs/conventions
printf 'verification: standard\n' >docs/conventions/testing.yaml
g add -A
g commit -q -m "shop"
ws_origin
g switch -q -c feat/cleanup
