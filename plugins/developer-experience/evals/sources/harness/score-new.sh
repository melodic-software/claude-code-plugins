#!/usr/bin/env bash
set -uo pipefail
EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shopt -s nullglob
for meta in "$EVALS"/results/*/*/*/run-*/meta.json; do
  dir="$(dirname "$meta")"
  [[ -f "$dir/score.json" ]] && continue
  [[ "$(basename "$(dirname "$(dirname "$(dirname "$dir")")")")" == SENT-* ]] && continue
  python3 -I "$EVALS/harness/score-deterministic.py" "$dir" >/dev/null 2>"$dir/score.err" || echo "FAIL $dir: $(tail -2 "$dir/score.err")"
done
