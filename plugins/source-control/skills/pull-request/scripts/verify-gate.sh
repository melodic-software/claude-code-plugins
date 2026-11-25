#!/usr/bin/env bash
# Exit codes:
#   0  record: stored; check: `pass` or `skipped` recorded for the head
#   1  invalid argument, or --dir names no directory
#   2  check: no result recorded for the head, or the state cannot be read
#   3  check: the recorded result for the head is `fail`
#   4  record --from-pre-ready: the base's `pre_ready` does not disable verify, or cannot be read;
#      nothing is recorded

# portability-scope: local state under the git directory; --from-pre-ready reads the base through read-pre-ready.sh's gh calls.
set -uo pipefail

usage() {
  cat <<'EOF'
verify-gate.sh: bind the ready flip's verify result to the head commit.

Usage:
  verify-gate.sh record --head <sha> --result pass|fail|skipped [--dir <checkout>]
  verify-gate.sh record --from-pre-ready --repo <owner/repo> --base <b> --head <sha> [--dir <checkout>]
  verify-gate.sh check  --head <sha> [--dir <checkout>]

  --head            the head commit the result binds to
  --result          the verify gate's result
  --from-pre-ready  record `skipped` only when the base's `pre_ready` turns verify off
  --repo, --base    the repository and base branch read for --from-pre-ready
  --dir             any checkout of the repository (default: the current directory);
                    $READY_VERIFY_DIR wins over it

Exit codes:
  0  record: stored; check: `pass` or `skipped` recorded for the head
  1  invalid argument, or --dir names no directory
  2  check: no result recorded for the head, or the state cannot be read
  3  check: the recorded result for the head is `fail`
  4  record --from-pre-ready: the base's `pre_ready` does not disable verify, or cannot be read;
     nothing is recorded
EOF
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

HEAD_SHA="" RESULT="" CHECKOUT="" FROM_PRE_READY=0 REPO="" BASE=""
while (($# > 0)); do
  case "$1" in
  --head | --result | --repo | --base)
    (($# >= 2)) || die 1 "$1 needs a value"
    case "$1" in
    --head) HEAD_SHA="$2" ;;
    --result) RESULT="$2" ;;
    --repo) REPO="$2" ;;
    *) BASE="$2" ;;
    esac
    shift 2
    ;;
  --from-pre-ready)
    FROM_PRE_READY=1
    shift
    ;;
  --dir)
    (($# >= 2)) && [[ -n "$2" && -z "$CHECKOUT" ]] || die 1 "--dir needs one value and is given once"
    CHECKOUT="$2"
    shift 2
    ;;
  *) die 1 "unknown argument $(printf '%q' "$1") (use --help)" ;;
  esac
done
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || die 1 "--head must be a full 40-character commit sha"
if ((FROM_PRE_READY)); then
  [[ "$CMD" == record ]] || die 1 "--from-pre-ready is a record option"
  [[ -z "$RESULT" ]] || die 1 "--from-pre-ready takes no --result: the result comes from the base's pre_ready"
  [[ -n "$REPO" && -n "$BASE" ]] || die 1 "--from-pre-ready needs --repo and --base"
else
  [[ -z "$REPO" && -z "$BASE" ]] || die 1 "--repo and --base go with --from-pre-ready"
fi
CHECKOUT="${CHECKOUT:-.}"
[[ -d "$CHECKOUT" ]] || die 1 "--dir $(printf '%q' "$CHECKOUT") is not a directory"

dir="${READY_VERIFY_DIR:-}"
if [[ -z "$dir" ]]; then
  dir=$(git -C "$CHECKOUT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die 2 "$(printf '%q' "$CHECKOUT") is not in a git repository, and READY_VERIFY_DIR is unset"
  dir+=/ready-verify
fi
file="$dir/$HEAD_SHA"

if ((FROM_PRE_READY)); then
  steps=$(bash "$(dirname "${BASH_SOURCE[0]}")/read-pre-ready.sh" --repo "$REPO" --base "$BASE") ||
    die 4 "the pre_ready read failed; nothing is recorded"
  awk -F '\t' 'NR == 1 && !($1 == "source" && $2 == "config" && NF == 2) { exit 1 }
    $1 == "verify" && $2 == "disabled" && NF == 2 { off = 1 } END { exit !off }' <<<"$steps" ||
    die 4 "pre_ready at $(printf '%q' "$BASE") in $(printf '%q' "$REPO") does not disable verify ($(head -n 1 <<<"$steps" | tr '\t' ' ')); nothing is recorded, so run the verify gate"
  RESULT=skipped
fi

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
