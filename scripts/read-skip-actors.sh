#!/usr/bin/env bash
# Print the ratified review skip-actors list in the comma-separated, no-spaces
# form the ci-workflows reusable workflows take.
#
#   scripts/read-skip-actors.sh [<file>]
#
# The list itself lives in .github/claude-skip-actors (one actor per line) —
# the single statement of ADR 0002's skip-actor exception; this script owns
# the one parse of it. Consumers: the claude-security-review caller reads the
# lane's `skip-actors` input through it, the claude-review caller reads its
# evidence guard's SKIP_ACTORS through it, and both evidence guards default
# from it when SKIP_ACTORS is not in the environment. <file> overrides the
# committed path so a caller can hand in a copy read from another ref (the
# security caller reads the PR's BASE copy, mirroring the reusable's
# `paths-file` discipline).
#
# FAIL CLOSED ON SHAPE: a missing file, an empty active set, or an entry that
# could corrupt the comma-joined form (embedded comma or whitespace) exits 2
# with nothing on stdout. Printing an empty or mangled list would silently
# rewrite the exception, which is the drift this file replaced.
#
# Exit: 0 list printed; 2 usage, unreadable file, or a malformed entry.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

if [[ $# -gt 1 ]]; then
  echo "usage: $(basename "$0") [<file>]" >&2
  exit 2
fi
file="${1:-$SCRIPT_DIR/../.github/claude-skip-actors}"

actors=()
# `inline`: entries are actor logins, never regexes, and a login cannot
# contain `#`.
read_list::into actors "$file" --comments inline || exit 2

if [[ ${#actors[@]} -eq 0 ]]; then
  echo "read-skip-actors: $file names no actors; an empty exception must be an explicit consumer decision, not a parsed-away file" >&2
  exit 2
fi
for actor in "${actors[@]}"; do
  if [[ "$actor" == *[,[:space:]]* ]]; then
    echo "read-skip-actors: malformed entry (comma or whitespace) in $file: $actor" >&2
    exit 2
  fi
done

(
  IFS=,
  printf '%s\n' "${actors[*]}"
)
