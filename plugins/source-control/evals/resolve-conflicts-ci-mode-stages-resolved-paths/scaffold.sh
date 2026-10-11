#!/usr/bin/env bash
# The lane's runner merged main into the PR head with --no-commit; src/http/retry.ts and
# docs/retry.md conflict. A post-index-change hook records, on every index write, which paths
# are still unmerged and which have unstaged edits, so the graders read the final index state.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config rerere.enabled false

mkdir -p src/http docs
cat > src/http/retry.ts <<'TS'
export interface RetryOptions {
  maxRetries: number;
  delayMs: number;
}

export const defaultRetryOptions: RetryOptions = {
  maxRetries: 3,
  delayMs: 200,
};
TS
cat > docs/retry.md <<'MD'
# Retry

Requests retry on failure.

## Options

- `maxRetries`: how many times a request is tried.
- `delayMs`: the wait between tries.
MD
git add .
git commit -q -m "feat(http): retry options"

git checkout -q -b feature/jitter
cat > src/http/retry.ts <<'TS'
export interface RetryOptions {
  maxRetries: number;
  backoffJitter: boolean;
  delayMs: number;
}

export const defaultRetryOptions: RetryOptions = {
  maxRetries: 3,
  backoffJitter: false,
  delayMs: 200,
};
TS
cat > docs/retry.md <<'MD'
# Retry

Requests retry on failure.

## Options

- `maxRetries`: how many times a request is tried.
- `backoffJitter`: spread retries randomly across the delay window.
- `delayMs`: the wait between tries.

## Jitter

With `backoffJitter` on, each wait is a random time up to `delayMs`, so clients that failed
together do not retry together.
MD
git add src/http/retry.ts docs/retry.md
git commit -q -m "feat(http): add backoffJitter option" -m "Synchronized retries from many clients hit the API in waves; jitter spreads them out. Off by default. Refs NET-41."

git checkout -q main
cat > src/http/retry.ts <<'TS'
export interface RetryOptions {
  maxAttempts: number;
  delayMs: number;
}

export const defaultRetryOptions: RetryOptions = {
  maxAttempts: 3,
  delayMs: 200,
};
TS
cat > docs/retry.md <<'MD'
# Retry

Requests retry on transient failures: 5xx responses and timeouts.

## Options

- `maxAttempts`: how many times a request is tried, the first try included.
- `delayMs`: the wait between tries.
MD
git add src/http/retry.ts docs/retry.md
git commit -q -m "refactor(http): rename maxRetries to maxAttempts" -m "The count includes the first try, so 'retries' was off by one in every caller's head. The docs now say which failures retry. Refs NET-38."

git checkout -q feature/jitter
git merge --no-commit --no-ff main >/dev/null 2>&1 || true
test -f .git/MERGE_HEAD
test "$(git diff --name-only --diff-filter=U | sort | tr '\n' ' ')" = "docs/retry.md src/http/retry.ts "

cat > .git/hooks/post-index-change <<'SH'
#!/bin/sh
[ -n "${EVAL_INDEX_HOOK:-}" ] && exit 0
EVAL_INDEX_HOOK=1
export EVAL_INDEX_HOOK
{
  echo unmerged:
  git ls-files -u | cut -f2 | sort -u
  echo unstaged:
  git diff --name-only
  echo end
} > "$(git rev-parse --git-dir)/eval-index-state"
SH
chmod +x .git/hooks/post-index-change
