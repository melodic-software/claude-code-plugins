#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 0
gate="$SCRIPT_DIR/check-changelog-fragments.sh"
self="$(basename "$0")"
remote="${1:-origin}"
zero=0000000000000000000000000000000000000000

head_sha="$(git rev-parse HEAD 2>/dev/null)" || exit 0
default="$(git symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>/dev/null)" || default="$remote/main"
default_branch="refs/heads/${default#"$remote"/}"

check=0
while IFS=' ' read -r local_ref local_sha remote_ref _; do
  [[ -n "${local_ref:-}" ]] || continue
  [[ "$local_sha" != "$zero" ]] || continue
  [[ "$remote_ref" == refs/heads/* ]] || continue
  [[ "$remote_ref" != "$default_branch" ]] || continue
  [[ "$local_sha" == "$head_sha" ]] || {
    echo "$self: $local_ref is not HEAD; its fragments are left to CI." >&2
    continue
  }
  check=1
done

((check)) || exit 0
if ! changed_files::verify_base "$default"; then
  echo "$self: $default is not fetched; fragment checks left to CI." >&2
  exit 0
fi

status=0
"$gate" --check || status=$?
if ((status != 1)); then
  "$gate" --check-required "$default" || status=$?
fi
case "$status" in
0) exit 0 ;;
1)
  echo "$self: fix the fragment finding above, commit, and push again (ADR 0048; scripts/new-changelog-fragment.sh writes one)." >&2
  exit 1
  ;;
*)
  echo "$self: the fragment gate could not run (exit $status); left to CI." >&2
  exit 0
  ;;
esac
