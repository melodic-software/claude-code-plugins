#!/usr/bin/env bash
# Tracked markdown and cross-cutting configs whose checks log to .calls.log, a typos config at the
# root that opts into cross-cutting, and no config any other ecosystem has for the source file. A
# markdown file and a source file only cross-cutting covers changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude tools src docs _typos.toml
eval_logger
eval_eco markdown '["*.md"]' check
eval_eco cross-cutting '["**"]' check
mkdir -p src docs
printf '[default.extend-words]\nfabrikam = "fabrikam"\n' >_typos.toml
printf '# Guide\n\nStart here.\n' >docs/guide.md
printf 'pub fn total(a: u32, b: u32) -> u32 {\n    a + b\n}\n' >src/lib.rs
g add -A
g commit -q -m "guide and library"
printf '# Guide\n\nStart here, then read the FAQ.\n' >docs/guide.md
printf 'pub fn total(a: u32, b: u32) -> u32 {\n    a.saturating_add(b)\n}\n' >src/lib.rs
