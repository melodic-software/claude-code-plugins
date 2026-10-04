#!/usr/bin/env bash
# Resolve the ref every diff-scoped step of ci.yml diffs against, for the
# `scope` job's "Resolve the diff base" step.
#
#   scripts/resolve-diff-base.sh
#
# Reads GITHUB_EVENT_NAME and BASE_REF; writes `ref=<base>` to $GITHUB_OUTPUT,
# or nothing for the whole tree. Always exits 0.
#
# - pull_request: origin/$BASE_REF.
# - anything else (merge group, schedule, dispatch): the whole tree.
set -uo pipefail

event=${GITHUB_EVENT_NAME:-}
output=${GITHUB_OUTPUT:-/dev/null}

case "$event" in
pull_request)
  echo "ref=origin/${BASE_REF:-}" >>"$output"
  ;;
*)
  echo "::notice::A $event run has no diff base; this $event run tests the whole tree."
  ;;
esac
exit 0
