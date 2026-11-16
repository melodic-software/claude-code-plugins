#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/comment-tooling-seed.sh"
git init -q
mkdir -p docs/adr
printf '%s\n' \
  '# 7. Two retries for the status call' \
  '' \
  'Status: accepted' \
  '' \
  'The status call retries twice, because the upstream API returns 502 on a cold start.' \
  'Rejected: unbounded retries, which hide a real outage.' >docs/adr/0007-retry-budget.md
# shellcheck disable=SC2016 # the fixture's $attempt is literal script text
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '# See docs/adr/0007' \
  'set -euo pipefail' \
  '' \
  'retries=2' \
  '# See docs/adr/0007: two retries because the upstream API returns 502 on a cold start' \
  'for ((attempt = 1; attempt <= retries; attempt++)); do' \
  '  # print the attempt number' \
  '  echo "attempt $attempt"' \
  'done' >fetch.sh
git add docs/adr/0007-retry-budget.md fetch.sh
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
