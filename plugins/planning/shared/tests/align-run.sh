#!/usr/bin/env bash
# One part of the page alignment check, run by align-<part>.test.sh: align.js over the sizes its PARTS puts in
# <part>, every view and theme at each. align.js seeds its own sessions through share.sh ensure-running on spare
# ports (fake cloudflared), and refuses the run while a part has no wrapper or a size sits in two parts. Passes only
# when align.js exits 0 and its last line is PASS n / n with n above 0. Locally a missing node, playwright-core or
# Chromium skips green; under CI=true it fails.
#   bash plugins/planning/shared/tests/align-run.sh <part>
# Narrow a run with ALIGN_VIEWS (comma list of view names) and ALIGN_SIZES (comma list of WxH, e.g. 390x844).
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
