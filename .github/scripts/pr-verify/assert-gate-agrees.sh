#!/usr/bin/env bash
# assert-gate-agrees.sh: the "Assert the gate and the resolver agree" step
# that pr-verify.yml, pr-verify-capture.yml and pr-rate-merge-risk.yml each run
# after the resolver: fails when the trigger gate and resolve-pr.mjs name
# different pull requests or heads. Run with bash from the workspace root,
# with GATE_PR, GATE_HEAD, PR_NUMBER and HEAD_SHA from the step env. errexit
# and pipefail match the step shell it replaces (the workflows' `shell: bash`).
# shellcheck disable=SC2154 # the step env sets GATE_PR, GATE_HEAD, PR_NUMBER and HEAD_SHA
set -eo pipefail

if [[ "$GATE_PR" != "$PR_NUMBER" ]] || [[ "$GATE_HEAD" != "$HEAD_SHA" ]]; then
  echo "::error::the trigger gate and the resolver name different pull requests or heads"
  exit 1
fi
