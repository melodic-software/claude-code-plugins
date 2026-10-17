#!/usr/bin/env bash
# The browser suites: every ui_*.js beside this file, UI_JOBS at a time (default 6), each into its own buffer printed
# whole in suite order. Each seeds its own session through share.sh ensure-running on spare ports (fake cloudflared),
# prints SKIP and exits 0 without playwright-core and a Chromium, and exits non-zero on a failed check. A suite timed
# to the millisecond (SERIAL) runs alone after the rest, since parallel load slows it past its own limits. Passes only
# when every suite exits 0.
#   bash plugins/planning/shared/tests/ui.test.sh
# test-scope: plugins/planning/shared/tests/browser_harness.js plugins/planning/shared/tests/harness-open.js
# test-scope: plugins/planning/shared/tests/ui_*.js plugins/planning/shared/web/*
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
command -v node >/dev/null || {
  echo "SKIP: node is not on PATH" # silent-skip-ok: a browser suite needs node
  exit 0
}
max=${UI_JOBS:-6}
[[ $max =~ ^[1-9][0-9]*$ ]] || {
  echo "UI_JOBS must be a whole number above 0, not: $max" >&2
  exit 2
}
SERIAL=" ui_snappy.js "
out=$(mktemp -d)
trap 'rm -rf "${out:?}"' EXIT
run() {
  node "$here/$1" >"$out/$1.log" 2>&1
  echo $? >"$out/$1.rc"
}
suites=()
for f in "$here"/ui_*.js; do suites+=("${f##*/}"); done
for s in "${suites[@]}"; do
  [[ $SERIAL == *" $s "* ]] && continue
  while (($(jobs -rp | wc -l) >= max)); do wait -n; done
  run "$s" &
done
wait
for s in "${suites[@]}"; do [[ $SERIAL == *" $s "* ]] && run "$s"; done
failed=()
for s in "${suites[@]}"; do
  echo "== $s"
  cat "$out/$s.log"
  [[ $(cat "$out/$s.rc" 2>/dev/null) == 0 ]] || failed+=("$s")
done
((${#failed[@]} == 0)) && exit 0
echo "FAIL: ${failed[*]}" >&2
exit 1
