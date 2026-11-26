#!/usr/bin/env bash
# Exit 0 = condition length is within the limit (count <= limit)
# Exit 1 = condition exceeds the limit (count > limit)
# Exit 2 = usage or environment error (bad/missing --limit, empty condition, ...)

set -uo pipefail

usage() {
  cat <<'TXT'
Mechanical character-length gate for a drafted /goal completion condition.

Usage: bash goal-condition-length.sh --limit <N> [--file <path>]
  --limit  the documented character limit (required)
  --file   the condition file (default stdin)
  --help   print this help

Exit 0 within the limit; 1 over it; 2 usage or environment error.
TXT
}

die() {
  echo "error: $1" >&2
  exit 2
}

limit=""
file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --limit)
    limit="${2-}"
    shift 2 || die "--limit needs a value"
    ;;
  --limit=*)
    limit="${1#*=}"
    shift
    ;;
  --file)
    file="${2-}"
    shift 2 || die "--file needs a value"
    ;;
  --file=*)
    file="${1#*=}"
    shift
    ;;
  *)
    die "unknown argument: $1"
    ;;
  esac
done

[[ -n "$limit" ]] || die "--limit <N> is required (pass the current limit read from the official /goal docs)"
if ! [[ "$limit" =~ ^[0-9]+$ ]] || [[ "$limit" -eq 0 ]]; then
  die "--limit must be a positive integer, got: $limit"
fi

if [[ -n "$file" ]]; then
  [[ -f "$file" ]] || die "--file not found: $file"
  condition="$(cat -- "$file")"
elif [[ -t 0 ]]; then
  die "no condition to read: stdin is a terminal; pipe the condition in or pass --file <path>"
else
  condition="$(cat)"
fi

[[ -n "$condition" ]] || die "empty condition (nothing to measure)"

if command -v perl >/dev/null 2>&1; then
  chars="$(printf '%s' "$condition" | perl -CSAD -e 'my $c = do { local $/; <STDIN> }; print length $c;')"
else
  chars="$(printf '%s' "$condition" | wc -m | tr -d '[:space:]')"
fi

[[ "$chars" =~ ^[0-9]+$ ]] || die "character count failed (counter returned: '${chars:-<empty>}')"

status=ok
[[ "$chars" -gt "$limit" ]] && status=over
echo "chars=$chars limit=$limit status=$status"
[[ "$status" == ok ]]
