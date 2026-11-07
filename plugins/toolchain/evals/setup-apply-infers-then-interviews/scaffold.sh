#!/usr/bin/env bash
# An unconfigured repository holding a uv-managed Python package, a Biome-linted TypeScript package
# and shell scripts, with no .claude/ecosystems/ directory.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude api web scripts
mkdir -p api/src/ledger web/src scripts
printf '[project]\nname = "ledger"\nversion = "0.1.0"\n\n[dependency-groups]\ndev = ["pytest>=8", "ruff>=0.6"]\n' >api/pyproject.toml
printf 'version = 1\nrequires-python = ">=3.12"\n' >api/uv.lock
printf 'def balance(entries):\n    return sum(entries)\n' >api/src/ledger/balance.py
printf '{\n  "name": "ledger-web",\n  "private": true,\n  "scripts": { "test": "vitest run" },\n  "devDependencies": { "@biomejs/biome": "2.3.2", "vitest": "4.0.6" }\n}\n' >web/package.json
printf '{ "formatter": { "enabled": true }, "linter": { "enabled": true } }\n' >web/biome.json
printf 'export const total = (a: number, b: number): number => a + b;\n' >web/src/total.ts
printf '#!/usr/bin/env bash\nset -euo pipefail\necho deploy\n' >scripts/deploy.sh
g add -A
g commit -q -m "ledger monorepo"
