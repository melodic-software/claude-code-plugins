#!/usr/bin/env bash
# A tracked markdown config whose check logs to .calls.log, and no config any ecosystem has for the
# source file beside it. A markdown file, a source file no ecosystem claims and a .png image changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude tools src docs assets
eval_logger
eval_eco markdown '["*.md"]' check
mkdir -p src docs assets
printf '# Guide\n\nStart here.\n' >docs/guide.md
printf 'pub fn total(a: u32, b: u32) -> u32 {\n    a + b\n}\n' >src/lib.rs
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR' >assets/logo.png
g add -A
g commit -q -m "guide, library and logo"
printf '# Guide\n\nStart here, then read the FAQ.\n' >docs/guide.md
printf 'pub fn total(a: u32, b: u32) -> u32 {\n    a.saturating_add(b)\n}\n' >src/lib.rs
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x01' >assets/logo.png
