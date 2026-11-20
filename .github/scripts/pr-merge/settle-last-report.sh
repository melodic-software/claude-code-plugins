#!/usr/bin/env bash
set -uo pipefail
dir=${1:?usage: settle-last-report.sh DIR [SETTLE_ARG...]}
shift
[[ -f "$dir/post-merge.json" && -f "$dir/post-merge-code" ]] || exit 1
[[ $(cat "$dir/post-merge-code") =~ ^[05]$ ]] || exit 1
sha=$(cat "$dir/post-merge-code-sha" 2>/dev/null || true)
scripts=${0%/.github/scripts/pr-merge/*}/plugins/source-control/skills/babysit-prs/scripts
limit=()
[[ -z "${SETTLE_TIMEOUT:-}" ]] || limit=(timeout "$SETTLE_TIMEOUT")
exec "${limit[@]}" python3 "$scripts/babysit_verify_evidence.py" settle --idle-tick --repo "${REPO:?}" \
  --postmerge-result "$dir/post-merge.json" --code-sha "$sha" "$@"
