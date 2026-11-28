#!/usr/bin/env bash
set -uo pipefail

own() {
  echo "the shared trusted PR text is not used ($1); this leg reads its own"
  exit 0
}

[[ ${SHARED_ATTEMPT:-} == "${RUN_ATTEMPT:-}" && -n ${RUN_ATTEMPT:-} ]] || own "another run attempt"
[[ ${SHARED_SHA256:-} =~ ^[0-9a-f]{64}$ ]] || own "no hash"
[[ ${SHARED_READ_AT:-} =~ ^[1-9][0-9]{0,11}$ ]] || own "no read time"
[[ ${SHARED_TEXT_MAX_AGE_MINUTES:-} =~ ^[1-9][0-9]{0,3}$ ]] || own "no age limit"
age=$(($(date +%s) - SHARED_READ_AT))
((age >= -60)) || own "a read time in the future"
((age <= SHARED_TEXT_MAX_AGE_MINUTES * 60)) || own "read ${age}s ago, past the ${SHARED_TEXT_MAX_AGE_MINUTES}-minute limit"
[[ ${SHARED_MAIN:-} =~ ^[0-9a-f]{40}$ ]] || own "no main commit"
main=$(git -C "${BASE_DIR:-}" rev-parse --verify HEAD 2>/dev/null) || own "this leg's main commit did not read"
[[ $SHARED_MAIN == "$main" ]] || own "another main commit"
[[ ${PR_NUMBER:-} =~ ^[1-9][0-9]{0,9}$ && ${SHARED_PR:-} == "$PR_NUMBER" ]] || own "another pull request"
[[ ${HEAD_SHA:-} =~ ^[0-9a-f]{40}$ && ${SHARED_HEAD:-} == "$HEAD_SHA" ]] || own "another head"
[[ -f ${SHARED_FILE:-} && ! -L $SHARED_FILE ]] || own "no artifact"
sum=$(sha256sum "$SHARED_FILE" | awk '{ print $1 }') || own "the artifact did not hash"
[[ $sum == "$SHARED_SHA256" ]] || own "the hash differs"
jq -e --argjson pr "$PR_NUMBER" '.pr.number == $pr and (.items | type) == "array"' "$SHARED_FILE" >/dev/null 2>&1 || own "the artifact names another pull request"
context=${CONTEXT_FILE:-}
[[ -n $context ]] || own "no context path"
if ! { mkdir -p "$(dirname "$context")" && cp "$SHARED_FILE" "$context"; }; then
  rm -f "$context"
  own "the copy failed"
fi
echo "shared=true" >>"${GITHUB_OUTPUT:?}"
echo "the shared trusted PR text matches this leg; no read of its own"
