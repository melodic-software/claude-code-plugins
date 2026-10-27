#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
# risk.py adds a cost-review hold when a patch raises a job's timeout. The
# branch drops the line anchor, so a commented-out timeout line counts too.
mkdir -p scripts/risk

cat >scripts/risk/risk.py <<'PY'
# Merge holds derived from a pull request's patch. A hold stops the merge lane
# until a person clears it.
import re

_TIMEOUT = re.compile(r"^\s*timeout-minutes:\s*(\d+)")


def _total(lines):
    return sum(int(m.group(1)) for line in lines if (m := _TIMEOUT.match(line)))


def raised_timeouts(patch):
    added = [line[1:] for line in patch.splitlines() if line.startswith("+") and not line.startswith("+++")]
    removed = [line[1:] for line in patch.splitlines() if line.startswith("-") and not line.startswith("---")]
    return _total(added) > _total(removed)


def holds(patch):
    found = []
    if raised_timeouts(patch):
        found.append("cost-review-required")
    return found
PY

git add .
git commit -q -m "feat: risk holds"

git checkout -q -b fix/timeout-inline-maps
cat >scripts/risk/risk.py <<'PY'
# Merge holds derived from a pull request's patch. A hold stops the merge lane
# until a person clears it.
import re

# Unanchored, so a timeout inside an inline map ({ timeout-minutes: 30 }) counts.
_TIMEOUT = re.compile(r"timeout-minutes:\s*(\d+)")


def _total(lines):
    return sum(int(m.group(1)) for line in lines if (m := _TIMEOUT.search(line)))


def raised_timeouts(patch):
    added = [line[1:] for line in patch.splitlines() if line.startswith("+") and not line.startswith("+++")]
    removed = [line[1:] for line in patch.splitlines() if line.startswith("-") and not line.startswith("---")]
    return _total(added) > _total(removed)


def holds(patch):
    found = []
    if raised_timeouts(patch):
        found.append("cost-review-required")
    return found
PY

git add .
git commit -q -m "fix(risk): count timeouts in inline maps"

mkdir -p .claude-lane
git diff main...HEAD >.claude-lane/pr.diff

cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/pr-context.md" .claude-lane/pr-context.md
