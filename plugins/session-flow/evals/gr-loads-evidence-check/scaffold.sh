#!/usr/bin/env bash
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src
cat >src/retry.ts <<'EOF'
export async function withRetry<T>(fn: () => Promise<T>, attempts = 5): Promise<T> {
  let last: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      last = err;
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
  throw last;
}
EOF
cat >src/client.ts <<'EOF'
import { withRetry } from "./retry";

export const fetchOrder = (id: string) => withRetry(() => fetch(`/orders/${id}`));
EOF
git add src
git commit -q -m "feat: retry loop"
