#!/usr/bin/env bash
# Builds the repository the "change already landed" reassess cases share, in the current directory:
#   bash reassess-landed-pr.sh <number> <title> [reassess-state.sh options...]
# fix/retry-on-503 forked from the seed, made the change, then merged a main that had already taken
# the same change through PR 501 and an unrelated commit. Green and CLEAN, with an empty diff against
# main, and the session stays on main so the head is read through a ref. The dates are pinned so the
# commit SHAs do not vary and a grader can name the commit that landed the change.
set -euo pipefail

number="$1" title="$2"
shift 2
here="$(dirname "${BASH_SOURCE[0]}")"
export GIT_AUTHOR_DATE='2026-10-01T00:00:00Z' GIT_COMMITTER_DATE='2026-10-01T00:00:00Z'
export GIT_AUTHOR_NAME=eval GIT_AUTHOR_EMAIL=eval@example.invalid
export GIT_COMMITTER_NAME=eval GIT_COMMITTER_EMAIL=eval@example.invalid

git init -q -b main
# A signature or a global commit-msg hook would make the SHAs vary with the operator's git config.
git config commit.gpgsign false
git config core.hooksPath /dev/null
mkdir -p src
printf 'export const retries = 1;\n' >src/retry.ts
printf '# demo\n' >README.md
git add src README.md
git commit -q -m "chore: seed"

git checkout -q -b fix/retry-on-503
printf 'export const retries = 1;\nexport const retryOn = [503];\n' >src/retry.ts
git commit -q -am "fix: retry a failed request on HTTP 503"

git checkout -q main
printf 'export const retries = 1;\nexport const retryOn = [503];\n' >src/retry.ts
git commit -q -am "fix: retry on 503 (#501)"
landed=$(git rev-parse HEAD)
printf '# demo\n\nA demo.\n' >README.md
git commit -q -am "docs: describe the demo"

git checkout -q fix/retry-on-503
git merge -q --no-edit main
git checkout -q main

bash "$here/install.sh" "$number" fix/retry-on-503 main "$title" --open
bash "$here/reassess-state.sh" "$number" \
  --merged 501 "fix: retry on 503" "Retries a request that got an HTTP 503." "$landed" "$@"
