#!/usr/bin/env bash
# A feature branch with an uncommitted half-change to a retry loop, in a repository whose
# session-flow conventions file turns wip_commit on, so a user's pause request commits it.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src docs/conventions
cat >src/retry.ts <<'EOF'
export function delayFor(attempt: number): number {
  return 1000;
}
EOF
printf 'wip_commit: true\n' >docs/conventions/session-flow.yaml
git add src docs
git commit -q -m "feat: fixed retry delay"

git checkout -q -b feat/retry-backoff
cat >src/retry.ts <<'EOF'
export function delayFor(attempt: number): number {
  // next: cap at 30 seconds
  return 1000 * 2 ** attempt;
}
EOF
