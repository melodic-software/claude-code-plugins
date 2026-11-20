# shellcheck shell=bash disable=SC2153,SC2154,SC2249,SC2292 # the step sets the uppercase env
if ! [[ $TIMEOUT =~ ^[1-9][0-9]{0,3}$ ]] || [ "$TIMEOUT" -le 15 ]; then
  echo "::error::a skill's run job needs a timeout-minutes over 15, to hold the launcher step"
  exit 1
fi
echo "step-minutes=$((TIMEOUT - 10))" >>"$GITHUB_OUTPUT"
echo "leg-minutes=$((TIMEOUT - 15))" >>"$GITHUB_OUTPUT"
if [[ ! "$ROLE" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo "::error::a skill needs a role of lowercase letters, digits and hyphens"
  exit 1
fi
if [ -z "$MODEL" ]; then
  echo "::error::the activity's model is default, which run-claude-cli cannot pass; name an alias"
  exit 1
fi
if [ "$GATING" != advisory ]; then
  echo "::error::a gate skill's verdict is not read from run-claude-cli"
  exit 1
fi
role=${ROLE^^}
echo "key-name=${role//-/_}_CLAUDE_API_KEY" >>"$GITHUB_OUTPUT"
echo "token-name=${role//-/_}_CLAUDE_CODE_OAUTH_TOKEN" >>"$GITHUB_OUTPUT"
