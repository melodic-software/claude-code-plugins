#!/usr/bin/env bash
# The browser suites, one after another: every ui_*.js beside this file. Each seeds its own session through
# share.sh ensure-running on spare ports (fake cloudflared), prints SKIP and exits 0 without playwright-core
# and a Chromium, and exits non-zero on a failed check. Passes only when every suite exits 0.
#   bash plugins/planning/shared/tests/ui.test.sh
# test-scope: plugins/planning/shared/tests/browser_harness.js plugins/planning/shared/tests/harness-open.js
# test-scope: plugins/planning/shared/tests/ui_*.js plugins/planning/shared/web/*
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
command -v node >/dev/null || {
  echo "SKIP: node is not on PATH" # silent-skip-ok: a browser suite needs node
  exit 0
}
failed=()
for f in "$here"/ui_*.js; do
  echo "== ${f##*/}"
  node "$f" || failed+=("${f##*/}")
done
((${#failed[@]} == 0)) && exit 0
echo "FAIL: ${failed[*]}" >&2
exit 1
