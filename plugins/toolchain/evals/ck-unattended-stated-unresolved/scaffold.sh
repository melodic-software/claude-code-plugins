#!/usr/bin/env bash
# A repository with no .claude/ecosystems record. CLAUDE.md states one command, the shell lint
# command (it logs to .calls.log through tools/run.sh); nothing states or implies a markdown command.
# One .sh file and one .md file changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude CLAUDE.md tools scripts docs
eval_logger
cat >CLAUDE.md <<'EOF'
# Project instructions

## Checks

Lint changed shell scripts with `bash tools/run.sh bash check <files>`.
EOF
mkdir -p scripts docs
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hi"' >scripts/app.sh
printf '%s\n' '# Guide' '' 'Run the app.' >docs/guide.md
g add -A
g commit -q -m "app"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'echo "hello"' >scripts/app.sh
printf '%s\n' '# Guide' '' 'Run the app with scripts/app.sh.' >docs/guide.md
