# shellcheck shell=bash disable=SC2153,SC2154,SC2249,SC2292 # the step sets the uppercase env
file="$DEPENDENCY_DIR/dependency.json"
run="$DEPENDENCY_DIR/context.json"
if [ "$(find "$DEPENDENCY_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)" != 2 ] || [ -L "$file" ] || [ ! -f "$file" ] ||
  [ -L "$run" ] || [ ! -f "$run" ] || [ "$(stat -c %s "$file")" -gt 1048576 ] || [ "$(stat -c %s "$run")" -gt 1048576 ]; then
  echo "::error::the dependency-context artifact is not exactly one dependency.json and one context.json of at most 1 MiB each"
  exit 1
fi
sum=$(sha256sum <"$file")
if ! [[ $CONTEXT_SHA256 =~ ^[0-9a-f]{64}$ ]] || [ "${sum%% *}" != "$CONTEXT_SHA256" ]; then
  echo "::error::the context file does not match the SHA-256 its job recorded"
  exit 1
fi
if [ "$(jq -r '.head_sha' "$file")" != "$HEAD_SHA" ] || [ "$(jq -r '.pr' "$file")" != "$PR_NUMBER" ]; then
  echo "::error::the context file was written for another head or PR; the next dispatch reads this one"
  exit 1
fi
