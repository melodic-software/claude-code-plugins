#!/usr/bin/env bash
# Extracts plugins/multi-agent and plugins/evals, as they stood at the pinned commit, into the
# run's workspace, so every arm answers the same questions against the same files.
# Usage: snapshot.sh (from a case's scaffold.sh; the workspace is the current directory)
set -euo pipefail

commit=af668bcb5c5380bb867be64f4d2cec96ce911bd3
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
if ! git -C "$repo" cat-file -e "$commit^{commit}" 2>/dev/null; then
  echo "snapshot.sh: commit $commit is not in $repo; run from a clone that holds it" >&2
  exit 1
fi
git -C "$repo" archive --format=tar "$commit" -- plugins/multi-agent plugins/evals | tar -xf -
