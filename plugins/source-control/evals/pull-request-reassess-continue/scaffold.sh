#!/usr/bin/env bash
# The PR adds a retry limit to src/retry.ts; main has moved on only in src/logger.ts.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
printf 'export const retries = 1;\n' >src/retry.ts
printf 'export const level = "info";\n' >src/logger.ts
git add src
git commit -q -m "chore: seed"
git checkout -q -b fix/retry-limit
printf 'export const retries = 3;\n' >src/retry.ts
git commit -q -am "fix: retry a failed request three times"
git checkout -q main
printf 'export const level = "warn";\n' >src/logger.ts
git commit -q -am "chore: log warnings and above (#620)"
landed=$(git rev-parse HEAD)
bash "$here/../fixtures/gh-forge/install.sh" 512 fix/retry-limit main "fix: retry a failed request three times" --open
bash "$here/../fixtures/gh-forge/reassess-state.sh" 512 \
  --merged 620 "chore: log warnings and above" "Quietens the logger." "$landed" \
  --issue 81 "Retry failed requests three times" "A failed request is retried only once. It should retry three times." \
  --closes 81 --body $'Closes #81\n\nRaises the retry limit to three.' "$@"
