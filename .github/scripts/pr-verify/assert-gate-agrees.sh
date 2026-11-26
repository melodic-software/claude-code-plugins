#!/usr/bin/env bash
# shellcheck disable=SC2154 # the step env sets GATE_PR, GATE_HEAD, PR_NUMBER and HEAD_SHA
set -eo pipefail

if [[ "$GATE_PR" != "$PR_NUMBER" ]] || [[ "$GATE_HEAD" != "$HEAD_SHA" ]]; then
  echo "::error::the trigger gate and the resolver name different pull requests or heads"
  exit 1
fi
