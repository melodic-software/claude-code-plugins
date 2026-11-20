# shellcheck shell=bash disable=SC2153,SC2154,SC2249,SC2292 # the step sets the uppercase env
file="$CI_DIR/context.json"
if [ "$(find "$CI_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)" != 1 ] || [ -L "$file" ] || [ ! -f "$file" ] ||
  [ "$(stat -c %s "$file")" -gt 1048576 ]; then
  echo "::error::the ci-context artifact is not exactly one context.json of at most 1 MiB"
  exit 1
fi
sum=$(sha256sum <"$file")
if ! [[ $CONTEXT_SHA256 =~ ^[0-9a-f]{64}$ ]] || [ "${sum%% *}" != "$CONTEXT_SHA256" ]; then
  echo "::error::the context file does not match the SHA-256 its job recorded"
  exit 1
fi
if [ "$(jq -r '.head_sha' "$file")" != "$HEAD_SHA" ]; then
  echo "::error::the context file was written for another head; the next dispatch reads this one"
  exit 1
fi
