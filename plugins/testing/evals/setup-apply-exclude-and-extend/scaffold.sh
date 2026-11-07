#!/usr/bin/env bash
# A TypeScript repository with a legacy/ folder, a *.it.ts integration test and a team file that
# already holds tdd_refactor_step: off.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main src legacy docs package.json
mkdir -p src legacy docs/conventions
printf '{ "name": "orders", "private": true, "devDependencies": { "vitest": "4.0.6" } }\n' >package.json
printf 'export const add = (a: number, b: number): number => a + b;\n' >src/add.ts
printf 'import { expect, test } from "vitest";\nimport { add } from "./add";\n\ntest("adds", () => {\n  expect(add(2, 3)).toBe(5);\n});\n' >src/add.test.ts
printf 'import { expect, test } from "vitest";\nimport { add } from "./add";\n\ntest("adds through the module boundary", () => {\n  expect(add(40, 2)).toBe(42);\n});\n' >src/add.it.ts
printf 'import { test } from "vitest";\n\ntest("old smoke", () => {});\n' >legacy/smoke.test.ts
printf 'tdd_refactor_step: off\n' >docs/conventions/testing.yaml
g add -A
g commit -q -m "orders"
