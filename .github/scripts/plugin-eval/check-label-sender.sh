#!/usr/bin/env bash
# Refuses an untrusted trigger verdict, or an `eval: run` label from anyone but
# a listed human. Reads PROCEED, REASON, LIST and SENDER_ID.
# shellcheck disable=SC2154,SC2292 # the step's body verbatim; the step env sets PROCEED, REASON, LIST and SENDER_ID
set -e
if [ "$PROCEED" != true ]; then
  echo "::error::the trigger is not trusted (reason: ${REASON:-unreadable})"
  exit 1
fi
if ! jq -e --argjson id "$SENDER_ID" 'any(.actors[]; .id == $id and .kind == "human")' "$LIST" >/dev/null; then
  echo "::error::untrusted-actor: the 'eval: run' label did not come from a listed human"
  exit 1
fi
