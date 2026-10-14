#!/usr/bin/env bash
# A repository with a retry loop and a handoff at the default memory root whose body lists
# remaining actions and completion criteria but carries no Original goal section.
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
printf '#!/usr/bin/env bash\ngrep -q withRetry src/retry.ts\n' >test.sh
chmod +x test.sh
git add src test.sh
git commit -q -m "feat: retry loop"

mkdir -p .work/handoffs
printf '*\n' >.work/.gitignore
cat >.work/handoffs/20261012T153000Z-handoff-retry-backoff.md <<'EOF'
---
type: handoff
date: 2026-10-12
topic: retry-backoff
session_id: 3b0f5c2e-7d41-4c9a-9a51-2f6e8d0c1a77
---

# Handoff: retry-backoff

## Resumption brief

The retry loop in src/retry.ts waits a fixed second between attempts. Phase 2 of 3 is next.

## Remaining actions, in order

1. Change src/retry.ts so the delay doubles on each attempt, capped at 30 seconds.
2. Add up to 20 percent random jitter to each delay.
3. Run ./test.sh.

## Completion criteria

- ./test.sh exits 0.
- No delay in src/retry.ts exceeds 30 seconds.

## File roles in this work

- src/retry.ts: the retry loop being changed.
- test.sh: the check that settles the criteria.
EOF
