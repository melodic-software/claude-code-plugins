#!/usr/bin/env bash
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
part=${1:-}
[[ $part =~ ^[a-z]$ ]] || {
  echo "usage: align-run.sh <part>, a part being a letter align.js PARTS names" >&2
  exit 2
}
command -v node >/dev/null || {
  [[ ${CI:-} == true ]] && {
    echo "FAIL: node is not on PATH" >&2
    exit 1
  }
  echo "SKIP: node is not on PATH" # silent-skip-ok: a browser suite needs node locally
  exit 0
}
out=$(ALIGN_PART=$part node "$here/align.js" 2>&1)
code=$?
printf '%s\n' "$out"
last=$(printf '%s\n' "$out" | tail -n 1)
if [[ ${CI:-} == true && $last == SKIP:* ]]; then
  echo "FAIL: align.js skipped for want of a browser under CI=true" >&2
  exit 1
fi
[[ $last == SKIP:* ]] && exit 0
if [[ $code == 0 && $last =~ ^PASS\ ([0-9]+)\ /\ ([0-9]+)$ && ${BASH_REMATCH[1]} == "${BASH_REMATCH[2]}" && ${BASH_REMATCH[1]} -gt 0 ]]; then
  exit 0
fi
echo "FAIL: align.js exit $code, last line: $last" >&2
exit 1
