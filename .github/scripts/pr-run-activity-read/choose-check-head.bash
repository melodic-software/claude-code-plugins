# shellcheck shell=bash disable=SC2153,SC2154,SC2249,SC2292 # the step sets the uppercase env
out() { printf 'post=true\nsha=%s\nforged=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"; }
valid() { [[ $1 =~ ^[0-9a-f]{40}$ ]]; }
if [ -z "$RUN_HEAD" ] && [ "$PR_MISMATCH" != true ]; then
  gated=$CALLER_HEAD
  valid "$gated" || gated=$EVENT_HEAD
  if [ "$TRUSTED_SKIP" = true ] || [ "$POST_DECLINE" = false ] || ! valid "$gated"; then
    out "" false
    if [ "$BROKER_STOP" = true ]; then echo "not-run-reason=kill-switch" >>"$GITHUB_OUTPUT"; fi
  else
    out "$gated" false
    echo "not-run-reason=not-assessed" >>"$GITHUB_OUTPUT"
  fi
  exit 0
fi
gated=()
for sha in "$CALLER_HEAD" "$EVENT_HEAD"; do
  if valid "$sha"; then gated+=("$sha"); fi
done
targets=("${gated[@]}")
if valid "$API_HEAD"; then targets+=("$API_HEAD"); fi
if [ "${#targets[@]}" -eq 0 ]; then
  echo "post=false" >>"$GITHUB_OUTPUT"
  echo "::error::no trusted PR head to post the check on; nothing is posted"
  exit 1
fi
if [ "$PR_MISMATCH" != true ] && [ -n "$RUN_HEAD" ]; then
  for sha in "${gated[@]}"; do
    if [ "$RUN_HEAD" = "$sha" ]; then
      out "$sha" false
      exit 0
    fi
  done
fi
echo "::error::the run job's head-sha or pr-number is not the gated PR's; failure is posted on the trusted head ${targets[0]}"
out "${targets[0]}" true
