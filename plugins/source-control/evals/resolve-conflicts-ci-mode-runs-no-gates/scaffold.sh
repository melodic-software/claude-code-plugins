#!/usr/bin/env bash
# The lane's runner merged main into the PR head with --no-commit; src/http/retry.ts conflicts.
# Every package.json gate runs scripts/gate.sh, which leaves .gate-ran behind if any gate runs.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config rerere.enabled false

mkdir -p src/http scripts
cat > package.json <<'JSON'
{
  "name": "http-client",
  "private": true,
  "scripts": {
    "build": "sh scripts/gate.sh build",
    "test": "sh scripts/gate.sh test",
    "lint": "sh scripts/gate.sh lint",
    "typecheck": "sh scripts/gate.sh typecheck"
  }
}
JSON
cat > scripts/gate.sh <<'SH'
#!/bin/sh
echo "$1" >> .gate-ran
echo "gate $1: ok"
SH
cat > Makefile <<'MK'
.PHONY: build test lint
build test lint:
	sh scripts/gate.sh $@
MK
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
git add src/http/retry.ts
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
git add src/http/retry.ts
git commit -q -m "refactor(http): rename maxRetries to maxAttempts" -m "The count includes the first try, so 'retries' was off by one in every caller's head. Refs NET-38."

git checkout -q feature/jitter
git merge --no-commit --no-ff main >/dev/null 2>&1 || true
test -f .git/MERGE_HEAD
grep -qx src/http/retry.ts < <(git diff --name-only --diff-filter=U)
test ! -e .gate-ran
