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
  # Sentinel range (not fixed line numbers) so the printed usage never silently
  # truncates when the header grows or shrinks on a future edit.
  sed -n '/^# Mechanical/,/^# Output/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
    shift 2 || {
      echo "error: --limit needs a value" >&2
      exit 2
    }
    ;;
  --limit=*)
    limit="${1#*=}"
    shift
    ;;
  --file)
    file="${2-}"
    shift 2 || {
      echo "error: --file needs a value" >&2
      exit 2
    }
    ;;
  --file=*)
    file="${1#*=}"
    shift
    ;;
  *)
    echo "error: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

# The limit is supplied by the caller (read live from the official docs); this
# gate deliberately has no default so a stale number can never be baked in.
if [[ -z "$limit" ]]; then
  echo "error: --limit <N> is required (pass the current limit read from the official /goal docs)" >&2
  exit 2
fi
if ! [[ "$limit" =~ ^[0-9]+$ ]] || [[ "$limit" -eq 0 ]]; then
  echo "error: --limit must be a positive integer, got: $limit" >&2
  exit 2
fi

# Read the condition. Command substitution strips trailing newlines, which is
# the desired normalization: a pasted /goal condition carries none.
if [[ -n "$file" ]]; then
  if [[ ! -f "$file" ]]; then
    echo "error: --file not found: $file" >&2
    exit 2
  fi
  condition="$(cat -- "$file")"
else
  condition="$(cat)"
fi

if [[ -z "$condition" ]]; then
  echo "error: empty condition (nothing to measure)" >&2
  exit 2
fi

# Count characters (Unicode code points), not bytes.
if command -v perl >/dev/null 2>&1; then
  chars="$(printf '%s' "$condition" | perl -CSAD -e 'my $c = do { local $/; <STDIN> }; print length $c;')"
else
  chars="$(printf '%s' "$condition" | wc -m | tr -d '[:space:]')"
fi

# Without set -e, a crashed counter would leave $chars empty and the -gt test
# below would error-and-fall-through to a false "status=ok". Fail loudly instead:
# a length gate that silently passes when its own counter broke is worse than useless.
if ! [[ "$chars" =~ ^[0-9]+$ ]]; then
  echo "error: character count failed (counter returned: '${chars:-<empty>}')" >&2
  exit 2
fi

if [[ "$chars" -gt "$limit" ]]; then
  echo "chars=$chars limit=$limit status=over"
  exit 1
fi

echo "chars=$chars limit=$limit status=ok"
exit 0
