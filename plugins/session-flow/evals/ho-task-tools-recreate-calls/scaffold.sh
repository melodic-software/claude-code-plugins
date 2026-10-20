#!/usr/bin/env bash
# A feature branch with an uncommitted half-change to a retry loop, a test script, and no
# remote, so a handoff has real in-flight state to save.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src
cat >src/retry.ts <<'EOF'
export function delayFor(attempt: number): number {
  return 1000;
}
EOF
printf '#!/usr/bin/env bash\ngrep -q "2 \\*\\* attempt" src/retry.ts\n' >test.sh
chmod +x test.sh
git add src test.sh
git commit -q -m "feat: fixed retry delay"

git checkout -q -b feat/retry-backoff
cat >src/retry.ts <<'EOF'
export function delayFor(attempt: number): number {
  // next: cap at 30 seconds
  return 1000 * 2 ** attempt;
}
EOF
