# shellcheck shell=bash disable=SC2153,SC2154,SC2249,SC2292 # the step sets the uppercase env
hold_label=needs-human
if [ -f .base/docs/conventions/work-items.yaml ]; then
  hold_label=$(yq -o=json -I=0 '.tracker' .base/docs/conventions/work-items.yaml |
    jq -er '.config.role_labels // {}
    | if has("human-gated") then .["human-gated"] | strings | select(length > 0) else "needs-human" end') || {
    echo "::error::cannot read the human-gated role label from the base docs/conventions/work-items.yaml"
    exit 1
  }
fi
if ! [[ $hold_label =~ ^[A-Za-z0-9][A-Za-z0-9\ ._:/-]*$ ]]; then
  echo "::error::the human-gated role label is malformed"
  exit 1
fi
lifted=false
case $HUMAN_GATE in
  fix-request) lifted=true ;;
  lane-escalation)
    recheck=$(mktemp)
    GITHUB_OUTPUT=$recheck LABEL=$hold_label node .base/.github/scripts/pr-unblock/gate-recheck.mjs
    if grep -qx 'lane-escalation=true' "$recheck"; then
      lifted=true
    fi
    ;;
esac
labels=$(jq -ce --arg human "$hold_label" --arg lifted "$lifted" \
  '["do-not-merge"] + (if $lifted == "true" then [] else [$human] end)
    + [(.selected["applies-when"]["labels-absent"] // [])[] | strings] | unique' \
  "$RESOLVED") || {
  echo "::error::cannot read the activity's labels-absent list from the resolved config"
  exit 1
}
echo "labels=$labels" >>"$GITHUB_OUTPUT"
