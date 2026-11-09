#!/usr/bin/env bash
# The PR adds a retry limit to src/retry.ts and a person has approved it; main has moved on only in
# src/logger.ts. The base's `pr_update_method: rebase` makes the update a rebase, and the session
# stays on the head branch, so `reassess --act` rebases from its own checkout.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# An operator's global signing or hooks would otherwise stop the rebase or the push.
git config commit.gpgsign false
git config core.hooksPath /dev/null
mkdir -p src docs/conventions
printf 'export const retries = 1;\n' >src/retry.ts
printf 'export const level = "info";\n' >src/logger.ts
printf 'pr_update_method: rebase\n' >docs/conventions/source-control.yaml
git add src docs
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
  --closes 81 --body $'Closes #81\n\nRaises the retry limit to three.' \
  --review reviewer APPROVED
git checkout -q fix/retry-limit
