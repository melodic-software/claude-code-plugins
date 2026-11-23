#!/usr/bin/env bash
set -euo pipefail

BIN=${BIN:?} RESOLVED=${RESOLVED:?} GITHUB_OUTPUT=${GITHUB_OUTPUT:?}
mkdir -p "$BIN"
for file in "$@"; do
  name=$(basename "$file" .sh)
  cp "$file" "$BIN/$name.sh"
  sum=$(sha256sum <"$BIN/$name.sh")
  echo "$name-sha256=${sum%% *}" >>"$GITHUB_OUTPUT"
done
no_progress=$(jq -r '.loop["no-progress"] // empty' "$RESOLVED")
if ! [[ $no_progress =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::the resolved config holds no loop.no-progress"
  exit 1
fi
echo "no-progress=$no_progress" >>"$GITHUB_OUTPUT"
