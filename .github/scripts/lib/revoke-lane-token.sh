#!/usr/bin/env bash
# revoke-lane-token.sh: revoke the lane App installation token in GH_TOKEN
# (DELETE installation/token on GITHUB_API_URL), so it stops working before
# its hour is up. Prints "the lane token is revoked" on a 204, else a warning
# that it was not; it always exits 0, since an unrevoked token only expires.
#
#   GH_TOKEN=<lane token> bash .base/.github/scripts/lib/revoke-lane-token.sh

# The header goes through stdin so the token never appears in a process
# listing.
status=$(printf 'Authorization: Bearer %s\n' "${GH_TOKEN:-}" |
  curl -sS -o /dev/null -w '%{http_code}' --max-time 30 -X DELETE -H @- \
    -H 'Accept: application/vnd.github+json' "${GITHUB_API_URL:-}/installation/token" || true)
if [[ "$status" = 204 ]]; then
  echo "the lane token is revoked"
else
  echo "::warning::the lane token was not revoked (DELETE $status); it expires within the hour"
fi
exit 0
