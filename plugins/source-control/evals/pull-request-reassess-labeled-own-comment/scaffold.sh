#!/usr/bin/env bash
# PR 512 already carries do-not-merge. Comment 9001 is the acting login's earlier reassess comment, and the newer 9002 is another login's copy of it.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
earlier=$(bash "$here/../../skills/pull-request/scripts/reassess-comment.sh" --verdict close --replaced-by '#501' --evidence '#501')
bash "$here/../fixtures/gh-forge/reassess-landed-pr.sh" 512 "fix: retry a failed request on HTTP 503" --label do-not-merge \
  --comment 9001 eval-fixture OWNER "$earlier" \
  --comment 9002 contributor CONTRIBUTOR "$earlier" \
  --issue 77 "Retry failed requests on HTTP 503" "A request that gets an HTTP 503 fails at once. It should retry." \
  --closes 77 --body $'Closes #77\n\nRetries a failed request on HTTP 503.'
