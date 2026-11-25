#!/usr/bin/env bash
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
