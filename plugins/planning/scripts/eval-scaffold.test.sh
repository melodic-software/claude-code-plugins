#!/usr/bin/env bash
# Contract: the nightly-etl eval scaffold seeds every fixture file under its
# real name, so the brainstorm eval cases that read them have a repository.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scaffold="$here/../evals/observed-fact-evidence-bar/scaffold.sh"
files=(
  etl/config.py.txt
  etl/extract.py.txt
  etl/load.py.txt
  etl/run_nightly.py.txt
  etl/transform.py.txt
  ops/crontab.txt
)
rc=0

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
(cd "$scratch" && bash "$scaffold")

for f in "${files[@]}"; do
  if [[ -s "$scratch/${f%.txt}" ]]; then
    printf 'ok: scaffold seeds %s\n' "${f%.txt}"
  else
    printf 'FAIL: scaffold did not seed %s\n' "$f" >&2
    rc=1
  fi
done
exit "$rc"
