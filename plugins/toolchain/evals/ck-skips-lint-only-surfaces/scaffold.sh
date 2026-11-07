#!/usr/bin/env bash
# Tracked bash, markdown, yaml and cross-cutting configs whose commands log to .calls.log, and the
# other covered ecosystems disabled. A workflow YAML, the README and a shell script changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude .github tools scripts README.md
eval_logger
eval_eco bash '["*.sh"]' check
eval_eco markdown '["*.md"]' check
eval_eco yaml '[".github/**/*.yml", ".github/**/*.yaml"]' check
eval_eco cross-cutting '["**"]' check
eval_eco_off dotnet python typescript powershell go
mkdir -p .github/workflows scripts
printf 'name: ci\non: [pull_request]\njobs:\n  test:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo test\n' >.github/workflows/ci.yml
printf '# deploy-kit\n\nDeploy helpers.\n' >README.md
printf '#!/usr/bin/env bash\nset -euo pipefail\necho deploy\n' >scripts/deploy.sh
g add -A
g commit -q -m "deploy-kit"
printf 'name: ci\non: [pull_request]\njobs:\n  test:\n    runs-on: ubuntu-24.04\n    timeout-minutes: 10\n    steps:\n      - run: echo test\n' >.github/workflows/ci.yml
printf '# deploy-kit\n\nDeploy helpers for the staging cluster.\n' >README.md
printf '#!/usr/bin/env bash\nset -euo pipefail\necho "deploy to staging"\n' >scripts/deploy.sh
