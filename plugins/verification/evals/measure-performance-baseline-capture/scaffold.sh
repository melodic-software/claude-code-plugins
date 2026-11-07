#!/usr/bin/env bash
# A small Python checkout whose approved plan states a measurable goal (a 2% faster parse_rows on
# bench.py) before any change is made, with no baseline captured yet.
set -euo pipefail
set -o noclobber
here="$(pwd -P)"
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/workspace-guard.sh" .git .gitignore README.md textkit bench.py .work
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES
g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c tag.gpgsign=false \
    -c user.name='Fabrikam Fixture' -c user.email='fixture@fabrikam.example' "$@"
}
g -c init.defaultBranch=main init -q --template=
if [[ "$(git rev-parse --show-toplevel)" != "${here}" ]]; then
  echo "git did not create a repository here: ${PWD}" >&2
  exit 3
fi
printf '.work/\n__pycache__/\n' >.gitignore
printf '# textkit\n\nSmall text helpers. Benchmark: python3 bench.py\n' >README.md
mkdir -p textkit
: >textkit/__init__.py
cat >textkit/rows.py <<'PY'
def parse_rows(text):
    rows = []
    for line in text.splitlines():
        if line.strip():
            rows.append([cell.strip() for cell in line.split(",")])
    return rows
PY
cat >bench.py <<'PY'
import time

from textkit.rows import parse_rows

TEXT = "\n".join("alpha, beta, gamma, %d" % i for i in range(60000))

start = time.perf_counter()
parse_rows(TEXT)
print("parse_rows: %.1f ms" % ((time.perf_counter() - start) * 1000))
PY
g add -A
g commit -q -m "textkit rows parser and bench"
mkdir -p .work/fast-rows
cat >.work/fast-rows/PLAN.md <<'MD'
# fast-rows

Approval: approved by the maintainer in the planning session

## Brief

Goal: make `parse_rows` in `textkit/rows.py` 2% faster on `python3 bench.py` by hoisting the
`line.strip()` call so each line is stripped once.

### Acceptance criteria

- AC1: `python3 bench.py` reports a parse_rows time at least 2% lower than before the change.

## Plan

### Phase 1: hoist the strip

- Edit `textkit/rows.py`.
MD
