#!/usr/bin/env bash
# The deterministic checks /testing:audit's judge pass runs around each judge
# dispatch, from the same judge-lib.sh functions the calibration harness uses.
#
#   judge-check.sh shape <model> <effort> <file> <ordinal> <start>-<end> <name>
#     Prints the block's shape key: blocks with one key have the same body
#     (the test's name taken out, whitespace runs collapsed), the same lines
#     around it in their file, the same repository, judge class, effort and
#     judge prompt, so the pass judges one of them and gives the rest its
#     verdict. Prints nothing for a block that has no key (a whole-file block,
#     a range the file does not hold, a file in no repository).
#   judge-check.sh comment-only <file> <diff file>
#     Exit 0 when every line the diff adds or removes is blank or a comment in
#     the test file's language, 1 when one is code.
#
# Exit 2 on a usage error.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$(cd "$HERE/../../../hooks" && pwd -P)"
# judge-lib.sh needs these set; neither check reads or writes its state.
# shellcheck disable=SC2034 # read by judge-lib.sh
DATA="" PKEY="" SID="" TPATH=""
# shellcheck source=../../../hooks/scanner-run.sh
source "$HOOK_DIR/scanner-run.sh"
# shellcheck source=../../../hooks/judge-lib.sh
source "$HOOK_DIR/judge-lib.sh"

usage() {
  echo "usage: judge-check.sh shape <model> <effort> <file> <ordinal> <start>-<end> <name>" >&2
  echo "       judge-check.sh comment-only <file> <diff file>" >&2
  exit 2
}

case "${1:-}" in
shape)
  (($# == 7)) || usage
  # shellcheck disable=SC2034 # judge::rkey keys on them
  MODEL="$2" EFFORT="$3"
  judge::file_repo "$4"
  [[ -n "$FREPO" ]] || exit 0
  judge::rkey "$4" "$5" "$6" "$7" "$FREPO"
  [[ -z "$RK" ]] || printf '%s\n' "$RK"
  ;;
comment-only)
  (($# == 3)) && [[ -f "$3" ]] || usage
  judge::comment_only "$2" "$(<"$3")"
  ;;
*) usage ;;
esac
