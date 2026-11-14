#!/usr/bin/env bash
# A Rust repository with a Cargo.toml and no .claude/ecosystems/rust.yaml (rust is neither recorded
# nor bundled, so only rung 2 can cover it); a .rs file changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude Cargo.toml src
mkdir -p src
printf '[package]\nname = "sum"\nversion = "0.1.0"\nedition = "2021"\n' >Cargo.toml
printf 'pub fn sum(a: i32, b: i32) -> i32 {\n    a + b\n}\n' >src/lib.rs
g add -A
g commit -q -m "sum"
printf 'pub fn sum(a: i32, b: i32) -> i32 {\n    a.saturating_add(b)\n}\n' >src/lib.rs
