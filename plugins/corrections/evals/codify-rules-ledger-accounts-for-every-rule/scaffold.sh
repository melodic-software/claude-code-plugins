#!/usr/bin/env bash
# A repository whose instruction files hold five rules, one for each outcome: a mechanical rule a
# past commit broke and fixed (a check with a proof), a mechanical rule nothing ever broke (no old
# ref, so held), a rule that needs judgment (prose), a rule package.json already states (delete),
# and a rule in a file AGENTS.md points to (read by following the pointer).
set -euo pipefail
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config commit.gpgsign false
mkdir -p src/internal .claude/rules .cursor/rules
cat >package.json <<'EOF'
{ "name": "widgets", "version": "1.0.0", "scripts": { "test": "node --test" } }
EOF
cat >src/logger.ts <<'EOF'
export const logger = { info: (msg: string) => process.stdout.write(`${msg}\n`) };
EOF
cat >src/internal/store.ts <<'EOF'
export const store = new Map<string, number>();
EOF
cat >src/widget.ts <<'EOF'
import { store } from "./internal/store";

export const addWidget = (name: string) => {
  store.set(name, (store.get(name) ?? 0) + 1);
  console.log("added", name);
};
EOF
cat >AGENTS.md <<'EOF'
# Widgets

Never call `console.log` in `src/`; log through `logger` from `src/logger.ts`.

Name functions so a reader understands them without the surrounding code.

Run the tests with `npm test`.

The API rules are in `.claude/rules/api.md`.
EOF
cat >.claude/rules/api.md <<'EOF'
Keep each exported API function focused on one job.
EOF
cat >.cursor/rules/boundaries.mdc <<'EOF'
---
description: Module boundaries
alwaysApply: true
---

Only files under `src/internal/` and `src/widget.ts` may import from `src/internal/`.
EOF
git add .
git commit -q -m "feat: widgets"
cat >src/widget.ts <<'EOF'
import { store } from "./internal/store";
import { logger } from "./logger";

export const addWidget = (name: string) => {
  store.set(name, (store.get(name) ?? 0) + 1);
  logger.info(`added ${name}`);
};
EOF
git add .
git commit -q -m "fix: log through logger instead of console.log"
