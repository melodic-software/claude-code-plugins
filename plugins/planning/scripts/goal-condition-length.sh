#!/usr/bin/env bash
# Mechanical character-length gate for a drafted /goal completion condition.
#
# A language model cannot reliably count characters, so conformance to the
# /goal condition character limit is decided here — deterministically, with NO
# model involvement. The limit is NOT baked in: the caller passes the value it
# read from the current official docs at authoring time (--limit), so this gate
# never rots when the documented limit changes between Claude Code versions.
#
# Exit 0 = condition length is within the limit (count <= limit)
# Exit 1 = condition exceeds the limit (count > limit)
# Exit 2 = usage or environment error (bad/missing --limit, empty condition, ...)
#
# Usage:
#   bash goal-condition-length.sh --limit <N> [--file <path>]   # else reads stdin
#   bash goal-condition-length.sh --help
#
# Counting: Unicode code points ("characters"), locale-independent via perl when
# present, falling back to `wc -m`. A trailing newline (as a file editor adds)
# is not part of the pasted condition and is stripped before counting.
#
# Output (stdout, greppable): `chars=<n> limit=<N> status=<ok|over>`

set -uo pipefail

usage() {
  sed -n '/^# Mechanical/,/^# Output/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# No default limit, so a stale number is never baked in.
[[ -n "$limit" ]] || die "--limit <N> is required (pass the current limit read from the official /goal docs)"
if ! [[ "$limit" =~ ^[0-9]+$ ]] || [[ "$limit" -eq 0 ]]; then
  die "--limit must be a positive integer, got: $limit"
fi

# Command substitution strips trailing newlines; a pasted /goal condition carries none.
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

# A crashed counter leaves $chars empty, which the comparison below would grade "ok".
[[ "$chars" =~ ^[0-9]+$ ]] || die "character count failed (counter returned: '${chars:-<empty>}')"

status=ok
[[ "$chars" -gt "$limit" ]] && status=over
echo "chars=$chars limit=$limit status=$status"
[[ "$status" == ok ]]
