#!/usr/bin/env bash
# The browser suites: every ui_*.js beside this file, UI_JOBS at a time (default 2, or 6 under
# CI where the runner's memory is the job's own), each into its own buffer printed
# whole in suite order under `== <suite> <seconds>s`, then the 3 slowest. They start slowest first, by ui-timings.txt
# (one "<suite> <seconds>" per line, from a full run's headers; a suite it does not list starts last), so the longest
# is never the last to start. Each seeds its own session through share.sh ensure-running on spare ports (fake
# cloudflared), prints SKIP and exits 0 without playwright-core and a Chromium, and exits non-zero on a failed check.
# Under CI=true a missing node, playwright-core or Chromium fails this script instead of passing it.
# A suite timed to the millisecond (SERIAL) runs alone after the rest, since parallel load slows it past its own
# limits. Passes only when every suite exits 0.
#   bash plugins/planning/shared/tests/ui.test.sh
# test-scope: plugins/planning/shared/tests/browser_harness.js plugins/planning/shared/tests/harness-open.js
# test-scope: plugins/planning/shared/tests/ui_*.js plugins/planning/shared/web/*
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
command -v node >/dev/null || {
  [[ ${CI:-} == true ]] && { echo "FAIL: node is not on PATH" >&2; exit 1; }
  echo "SKIP: node is not on PATH" # silent-skip-ok: a browser suite needs node locally
  exit 0
}
default_jobs=2
[[ -n ${CI:-} ]] && default_jobs=6
max=${UI_JOBS:-$default_jobs}
[[ $max =~ ^[1-9][0-9]*$ ]] || {
  echo "UI_JOBS must be a whole number above 0, not: $max" >&2
  exit 2
}
SERIAL=" ui_snappy.js "
out=$(mktemp -d)
trap 'rm -rf "${out:?}"' EXIT
run() {
  local t0=$SECONDS
  node "$here/$1" >"$out/$1.log" 2>&1
  echo $? >"$out/$1.rc"
  echo $((SECONDS - t0)) >"$out/$1.s"
}
suites=()
for f in "$here"/ui_*.js; do suites+=("${f##*/}"); done
order=()
while read -r _ s; do order+=("$s"); done < <(for s in "${suites[@]}"; do
  t=$(awk -v s="$s" '$1 == s { print $2 }' "$here/ui-timings.txt" 2>/dev/null)
  echo "${t:--1} $s"
done | sort -s -k1,1nr)
for s in "${order[@]}"; do
  [[ $SERIAL == *" $s "* ]] && continue
  while (($(jobs -rp | wc -l) >= max)); do wait -n; done
  run "$s" &
done
wait
for s in "${suites[@]}"; do [[ $SERIAL == *" $s "* ]] && run "$s"; done
failed=()
for s in "${suites[@]}"; do
  echo "== $s $(cat "$out/$s.s" 2>/dev/null)s"
  cat "$out/$s.log"
  [[ $(cat "$out/$s.rc" 2>/dev/null) == 0 ]] || failed+=("$s")
  if [[ ${CI:-} == true ]] && grep -qE '^SKIP: (.*needs playwright-core|no Chromium to launch)' "$out/$s.log"; then
    echo "FAIL: $s skipped for want of a browser under CI=true" >&2
    failed+=("$s")
  fi
done
echo "slowest: $(for s in "${suites[@]}"; do echo "$(cat "$out/$s.s" 2>/dev/null) $s"; done | sort -k1,1nr | awk 'NR <= 3 { printf "%s%s %ss", (NR > 1 ? ", " : ""), $2, $1 }')"
((${#failed[@]} == 0)) && exit 0
echo "FAIL: ${failed[*]}" >&2
exit 1
