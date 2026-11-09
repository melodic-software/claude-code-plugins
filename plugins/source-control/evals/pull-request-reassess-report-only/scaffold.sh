#!/usr/bin/env bash
# The same PR state as pull-request-reassess-close-label-first, run without --act.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/gh-forge/reassess-landed-pr.sh" 512 "fix: retry a failed request on HTTP 503" \
  --issue 77 "Retry failed requests on HTTP 503" "A request that gets an HTTP 503 fails at once. It should retry." \
  --closes 77 --body $'Closes #77\n\nRetries a failed request on HTTP 503.'
