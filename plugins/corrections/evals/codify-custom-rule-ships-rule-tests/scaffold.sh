#!/usr/bin/env bash
# A TypeScript repository that already writes its own ESLint rules, each with a RuleTester test,
# and a findings file whose one row needs a new rule that resolves a value's type.
set -euo pipefail
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config commit.gpgsign false
mkdir -p src/billing eslint-rules
cat >package.json <<'EOF'
{ "name": "billing", "version": "1.0.0", "type": "module",
  "scripts": { "lint": "eslint src", "test:rules": "node --test eslint-rules" } }
EOF
cat >eslint.config.js <<'EOF'
import tseslint from "typescript-eslint";
import noDefaultExport from "./eslint-rules/no-default-export.js";

export default tseslint.config({
  files: ["src/**/*.ts"],
  languageOptions: { parserOptions: { projectService: true } },
  plugins: { local: { rules: { "no-default-export": noDefaultExport } } },
  rules: { "local/no-default-export": "error" },
});
EOF
cat >eslint-rules/no-default-export.js <<'EOF'
export default {
  meta: { type: "problem", messages: { named: "Use a named export." }, schema: [] },
  create: (context) => ({
    ExportDefaultDeclaration: (node) => context.report({ node, messageId: "named" }),
  }),
};
EOF
cat >eslint-rules/no-default-export.test.js <<'EOF'
import { RuleTester } from "eslint";
import rule from "./no-default-export.js";

new RuleTester().run("no-default-export", rule, {
  valid: ["export const a = 1;"],
  invalid: [{ code: "export default 1;", errors: [{ messageId: "named" }] }],
});
EOF
cat >src/secret.ts <<'EOF'
export type Secret<T> = T & { readonly __secret: unique symbol };
EOF
cat >src/logger.ts <<'EOF'
export const logger = { info: (...args: unknown[]) => console.log(JSON.stringify(args)) };
EOF
cat >src/billing/charge.ts <<'EOF'
import type { Secret } from "../secret";
import { logger } from "../logger";

export const charge = (card: { token: Secret<string>; last4: string }) => {
  const t = card.token;
  logger.info("charging", t);
};
EOF
git add .
git commit -q -m "feat: charge"
cat >findings.md <<'EOF'
---
type: review-findings
date: 2026-01-01T00:00:00Z
branch: fixture
tier: medium
---

## Findings

| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |
|------|------|------------|----------|------------|---------|--------|
| 1 | CRITICAL | high | src/billing/charge.ts:6 | code-reviewer | Passes `t`, a value typed `Secret<string>`, to `logger.info`, which writes it in plain text. The variable's name gives no hint of its type. | Fail any logger call that receives a value whose type is `Secret`, whatever the variable is called. |

## Unparsed

None.

## Surfaces

Ran: code-reviewer.
EOF
