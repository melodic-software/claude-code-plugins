#!/usr/bin/env bash
# A JavaScript package with no .claude/ecosystems record and no instructions file. Its package.json
# test script (it logs `typescript test` to .calls.log through tools/run.sh) is the one command its
# files imply; no build script, tsconfig or lint config exists. One .js file changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude tools src package.json
eval_logger
cat >package.json <<'EOF'
{
  "name": "cart",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "test": "bash tools/run.sh typescript test"
  }
}
EOF
mkdir -p src
printf '%s\n' 'export const sum = (a, b) => a + b;' >src/sum.js
g add -A
g commit -q -m "cart"
printf '%s\n' 'export const sum = (a, b) => Number(a) + Number(b);' >src/sum.js
