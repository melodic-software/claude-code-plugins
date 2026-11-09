#!/usr/bin/env bash
# PR 512's head is on a fork, so the origin holds only refs/pull/512/head; its change already landed through PR 501.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/gh-forge/reassess-landed-pr.sh" 512 "fix: retry a failed request on HTTP 503" --fork contributor \
  --issue 77 "Retry failed requests on HTTP 503" "A request that gets an HTTP 503 fails at once. It should retry." \
  --closes 77 --body $'Closes #77\n\nRetries a failed request on HTTP 503.'
