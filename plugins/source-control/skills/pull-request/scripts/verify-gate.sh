#!/usr/bin/env bash
# verify-gate.sh — Bind the ready flip's verify result to the head commit.
#
# The `ready` action's verify gate runs in its own Bash call, so its exit status cannot stop
# the later call that flips the draft. `record` writes the gate's result for one head commit;
# `check` runs in the same shell command as `gh pr ready` and refuses unless that exact head
# has a recorded `pass`, or a recorded `skipped` (the run was invoked with `--skip verify`).
# A result recorded for another head never counts, so a commit after the gate voids it.
#
# Usage:
#   verify-gate.sh record --head <sha> --result pass|fail|skipped
#   verify-gate.sh check  --head <sha>
#
# The result lives under the repository's git directory (`ready-verify/<sha>`), or under
# $READY_VERIFY_DIR when set.
#
# Exit codes:
#   0  record: stored; check: `pass` or `skipped` recorded for the head
#   1  invalid argument
#   2  check: no result recorded for the head, or the state cannot be read
#   3  check: the recorded result for the head is `fail`

# portability-scope: local state under the git directory; no forge call.
set -uo pipefail

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

die() {
  printf 'verify-gate: %s\n' "$2" >&2
  exit "$1"
}

(($# > 0)) || die 1 "a subcommand is required (use --help)"
case "$1" in
-h | --help) usage ;;
record | check) CMD="$1" ;;
*) die 1 "unknown subcommand $(printf '%q' "$1") (use --help)" ;;
esac
shift

HEAD_SHA="" RESULT=""
while (($# > 0)); do
  case "$1" in
  --head)
    (($# >= 2)) || die 1 "--head needs a value"
    HEAD_SHA="$2"
    shift 2
    ;;
  --result)
    (($# >= 2)) || die 1 "--result needs a value"
    RESULT="$2"
    shift 2
    ;;
  *) die 1 "unknown argument $(printf '%q' "$1") (use --help)" ;;
  esac
done
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || die 1 "--head must be a full 40-character commit sha"

dir="${READY_VERIFY_DIR:-}"
if [[ -z "$dir" ]]; then
  dir=$(git rev-parse --git-path ready-verify 2>/dev/null) || die 2 "not in a git repository, and READY_VERIFY_DIR is unset"
fi
file="$dir/$HEAD_SHA"

if [[ "$CMD" == record ]]; then
  case "$RESULT" in
  pass | fail | skipped) ;;
  *) die 1 "--result must be pass, fail or skipped" ;;
  esac
  mkdir -p "$dir" || die 2 "cannot create $dir"
  printf '%s\n' "$RESULT" >"$file" || die 2 "cannot write $file"
  exit 0
fi

[[ -z "$RESULT" ]] || die 1 "check takes no --result"
[[ -f "$file" ]] || die 2 "no verify result is recorded for head $HEAD_SHA; run the verify gate on this head and record it"
read -r recorded <"$file" || die 2 "cannot read $file"
case "$recorded" in
pass | skipped) exit 0 ;;
fail) die 3 "the verify gate failed on head $HEAD_SHA; fix it and run the gate again" ;;
*) die 2 "unreadable verify result for head $HEAD_SHA" ;;
esac
