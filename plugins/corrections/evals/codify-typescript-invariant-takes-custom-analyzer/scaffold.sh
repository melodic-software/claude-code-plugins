#!/usr/bin/env bash
set -euo pipefail
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config commit.gpgsign false
mkdir -p src/billing
cat >package.json <<'EOF'
{ "name": "billing", "version": "1.0.0", "scripts": { "lint": "eslint src", "test": "vitest" } }
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
