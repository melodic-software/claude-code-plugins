#!/usr/bin/env bash
# An unconfigured repository of shell scripts only, so bash is the one ecosystem inference finds.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude bin README.md
mkdir -p bin
printf '#!/usr/bin/env bash\nset -euo pipefail\necho backup\n' >bin/backup.sh
printf '#!/usr/bin/env bash\nset -euo pipefail\necho restore\n' >bin/restore.sh
printf 'Backup and restore scripts.\n' >README.md
g add -A
g commit -q -m "backup scripts"
