# shellcheck shell=bash disable=SC2153,SC2154,SC2249,SC2292 # the step sets the uppercase env
if [ -L "$VERDICT_FILE" ] || [ ! -f "$VERDICT_FILE" ] || [ "$(stat -c %s "$VERDICT_FILE")" -gt 49152 ]; then
  echo "::error::the dependency-verdict artifact holds no verdict of at most 49152 bytes"
  exit 1
fi
sum=$(sha256sum <"$VERDICT_FILE")
if ! [[ $VERDICT_SHA256 =~ ^[0-9a-f]{64}$ ]] || [ "${sum%% *}" != "$VERDICT_SHA256" ]; then
  echo "::error::the verdict does not match the SHA-256 the scan job recorded"
  exit 1
fi
verdict=$(jq -r 'if type == "object" and (.verdict | type) == "string" then .verdict else "" end' "$VERDICT_FILE") || verdict=""
case $verdict in
  merge | fix | close | escalate) ;;
  *) verdict="" ;;
esac
echo "verdict=$verdict" >>"$GITHUB_OUTPUT"
