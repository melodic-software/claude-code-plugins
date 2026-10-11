#!/usr/bin/env bash
# Contract: each eval scaffold seeds every fixture file under its real name,
# so the eval cases that read them have a workspace: the nightly-etl
# repository for the brainstorm cases, and the partner-feed tracker export for
# the wayfind work-mode cases.
# test-scope: plugins/planning/evals/observed-fact-evidence-bar/scaffold.sh plugins/planning/evals/work-*/scaffold.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
evals="$here/../evals"
rc=0

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# check_scaffold <case> <file>... : run the case's scaffold in a fresh
# directory and require each file, minus its .txt suffix, non-empty there.
check_scaffold() {
  local case="$1" dir="$scratch/$1" f
  shift
  mkdir -p "$dir"
  (cd "$dir" && bash "$evals/$case/scaffold.sh")
  for f in "$@"; do
    if [[ -s "$dir/${f%.txt}" ]]; then
      printf 'ok: %s scaffold seeds %s\n' "$case" "${f%.txt}"
    else
      printf 'FAIL: %s scaffold did not seed %s\n' "$case" "$f" >&2
      rc=1
    fi
  done
}

check_scaffold observed-fact-evidence-bar \
  etl/config.py.txt \
  etl/extract.py.txt \
  etl/load.py.txt \
  etl/run_nightly.py.txt \
  etl/transform.py.txt \
  ops/crontab.txt

for case in work-brief-respects-out-of-scope work-design-handoff-carries-map work-research-brief-carries-map; do
  check_scaffold "$case" tracker-export/items.md.txt tracker-export/map-300.md.txt
done

exit "$rc"
