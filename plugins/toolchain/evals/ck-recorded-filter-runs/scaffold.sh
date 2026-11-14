#!/usr/bin/env bash
# A repository whose tracked .claude/ecosystems/zig.yaml records an ecosystem no bundled default
# ships (its commands log to .calls.log); a .zig file changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude tools src
eval_logger
eval_eco zig '["*.zig"]' build test check
mkdir -p src
printf 'pub fn sum(a: i32, b: i32) i32 {\n    return a + b;\n}\n' >src/sum.zig
g add -A
g commit -q -m "sum"
printf 'pub fn sum(a: i32, b: i32) i32 {\n    return a +| b;\n}\n' >src/sum.zig
