#!/usr/bin/env bash
# Tracked typescript and bash configs whose every command logs to .calls.log; a .ts file and a bash
# script changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude tools src scripts package.json
eval_logger
eval_eco typescript '["*.ts", "package.json"]' build test check fix code-fix
eval_eco bash '["*.sh"]' build test check fix
mkdir -p src scripts
printf '{ "name": "storefront", "private": true }\n' >package.json
printf 'export const total = (a: number, b: number): number => a + b;\n' >src/cart.ts
printf '#!/usr/bin/env bash\nset -euo pipefail\necho release\n' >scripts/release.sh
g add -A
g commit -q -m "storefront"
printf 'export const total = (a: number, b: number): number => Math.round((a + b) * 100) / 100;\n' >src/cart.ts
printf '#!/usr/bin/env bash\nset -euo pipefail\necho "release to staging"\n' >scripts/release.sh
