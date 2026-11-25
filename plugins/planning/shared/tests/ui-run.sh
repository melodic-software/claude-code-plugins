#!/usr/bin/env bash
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
part=${1:-}
[[ $part == --check || $part =~ ^[a-z]$ ]] || {
  echo "usage: ui-run.sh <part> | --check, a part being a letter ui-parts.txt names" >&2
  exit 2
}
declare -A part_of=()
bad=0
while read -r s p _; do
  [[ -z $s || $s == \#* ]] && continue
  if [[ $s != ui_*.js || ! -f $here/$s ]]; then
    echo "ui-parts.txt: $s is no ui_*.js beside it" >&2
    bad=1
  elif [[ -n ${part_of[$s]+x} ]]; then
    echo "ui-parts.txt: $s is in more than one part" >&2
    bad=1
  elif [[ ! -f $here/ui-$p.test.sh ]]; then
    echo "ui-parts.txt: $s is in part '$p', which has no ui-$p.test.sh" >&2
    bad=1
  fi
  part_of[$s]=$p
done <"$here/ui-parts.txt"
suites=()
for f in "$here"/ui_*.js; do
  s=${f##*/}
  if [[ -z ${part_of[$s]+x} ]]; then
    echo "ui-parts.txt: $s is in no part" >&2
    bad=1
  elif [[ ${part_of[$s]} == "$part" ]]; then
    suites+=("$s")
  fi
done
((bad == 0)) || exit 2
[[ $part == --check ]] && exit 0
((${#suites[@]} > 0)) || {
  echo "ui-parts.txt puts no suite in part '$part'" >&2
  exit 2
}
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
SERIAL=" ui_snappy.js ui_telemetry.js "
out=$(mktemp -d)
trap 'rm -rf "${out:?}"' EXIT
mkdir "$out/t"
export TMPDIR="$out/t"
run() {
  local t0=$SECONDS
  node "$here/$1" >"$out/$1.log" 2>&1
  echo $? >"$out/$1.rc"
  echo $((SECONDS - t0)) >"$out/$1.s"
}
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
