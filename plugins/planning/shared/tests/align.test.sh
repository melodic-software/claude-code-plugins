#!/usr/bin/env bash
# Page alignment check over every view, size and theme: align.js seeds its own sessions through share.sh
# ensure-running on spare ports (fake cloudflared). Passes only when align.js exits 0 and its last line is
# PASS n / n with n above 0.
#   bash plugins/planning/shared/tests/align.test.sh
# Narrow a run with ALIGN_VIEWS (comma list of view names) and ALIGN_SIZES (comma list of WxH, e.g. 390x844).
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
command -v node >/dev/null || {
  echo "SKIP: node is not on PATH" # silent-skip-ok: a browser suite needs node
  exit 0
}
out=$(node "$here/align.js" 2>&1)
code=$?
printf '%s\n' "$out"
last=$(printf '%s\n' "$out" | tail -n 1)
[[ $last == SKIP:* ]] && exit 0
if [[ $code == 0 && $last =~ ^PASS\ ([0-9]+)\ /\ ([0-9]+)$ && ${BASH_REMATCH[1]} == "${BASH_REMATCH[2]}" && ${BASH_REMATCH[1]} -gt 0 ]]; then
  exit 0
fi
echo "FAIL: align.js exit $code, last line: $last" >&2
exit 1
