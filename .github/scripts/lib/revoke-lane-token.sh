#!/usr/bin/env bash

status=$(printf 'Authorization: Bearer %s\n' "${GH_TOKEN:-}" |
  curl -sS -o /dev/null -w '%{http_code}' --max-time 30 -X DELETE -H @- \
    -H 'Accept: application/vnd.github+json' "${GITHUB_API_URL:-}/installation/token" || true)
if [[ "$status" = 204 ]]; then
  echo "the lane token is revoked"
else
  echo "::warning::the lane token was not revoked (DELETE $status); it expires within the hour"
fi
exit 0
