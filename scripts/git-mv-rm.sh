#!/usr/bin/env bash
# Renames or removes files inside the checkout through git, so the index
# follows:
#
#   scripts/git-mv-rm.sh mv <source> <destination>
#   scripts/git-mv-rm.sh rm <path>...
#
# A file not yet tracked works too: it is recorded as intent-to-add first, the
# entry git mv and git rm need. rm removes a directory's contents and discards
# uncommitted edits to what it removes. Every path must be inside the checkout
# (the current directory; scripts/lib/checkout-path.sh), and git reads each
# one literally, never as a glob or pathspec magic. Exits 2 on a refused
# argument, else with git's status.
set -euo pipefail
# shellcheck source=scripts/lib/checkout-path.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/checkout-path.sh"
export GIT_LITERAL_PATHSPECS=1

usage() {
  echo "usage: git-mv-rm.sh mv <source> <destination> | git-mv-rm.sh rm <path>..." >&2
  exit 2
}

op=${1:-}
shift || usage
case $op in
  mv) [[ "$#" -eq 2 ]] || usage ;;
  rm) [[ "$#" -ge 1 ]] || usage ;;
  *) usage ;;
esac
for path in "$@"; do
  checkout_path::require "$path"
done
if [[ "$op" = mv ]]; then
  git add --intent-to-add -- "$1"
  git mv -- "$1" "$2"
else
  git add --intent-to-add -- "$@"
  git rm -r -f -q -- "$@"
fi
