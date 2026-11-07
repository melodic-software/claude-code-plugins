#!/usr/bin/env bash
# A tracked python config whose only command is a code-fix-cmd that logs to .calls.log; 43 Python
# files changed, over the default file-cap of 40.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude tools src
eval_logger
eval_eco python '["*.py"]' code-fix
mkdir -p src/handlers
for n in $(seq -w 1 43); do
  printf 'def handle_%s(event):\n    return event\n' "${n}" >"src/handlers/h${n}.py"
done
g add -A
g commit -q -m "handlers"
for n in $(seq -w 1 43); do
  printf 'import os\n\n\ndef handle_%s(event):\n    return event\n' "${n}" >"src/handlers/h${n}.py"
done
