#!/usr/bin/env bash
# A tracked bash config whose commands log to .calls.log, and a changed .sh script. The result store
# path, .git/toolchain-results, is a plain file, so record-result.mjs cannot write the record and
# exits 2.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude tools greet.sh
eval_logger
eval_eco bash '["*.sh"]' build test check
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hi"' >greet.sh
g add -A
g commit -q -m "greet and tools"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hello"' >greet.sh
printf 'not a directory\n' >.git/toolchain-results
