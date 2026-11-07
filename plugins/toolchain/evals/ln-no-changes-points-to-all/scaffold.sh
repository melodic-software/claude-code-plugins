#!/usr/bin/env bash
# A clean working tree on the default branch, pushed to an origin whose HEAD names it, so neither
# git status nor the branch diff yields a change. A tracked bash config logs to .calls.log.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init trunk .claude tools scripts .remote.git
eval_logger
eval_eco bash '["*.sh"]' check
mkdir -p scripts
printf '#!/usr/bin/env bash\nset -euo pipefail\necho release\n' >scripts/release.sh
g add -A
g commit -q -m "release script"
eval_repo_origin
