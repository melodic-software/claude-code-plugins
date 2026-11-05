#!/usr/bin/env bash
# A git repository with one tracked pytest file and a ruff select that leaves out PT011, so check's lint section has a FINDING.
set -euo pipefail
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p tests
cat >pyproject.toml <<'TOML'
[project]
name = "demo"
version = "0.1.0"

[tool.ruff.lint]
select = ["E", "F", "PLR0124"]
TOML
cat >tests/test_math.py <<'PY'
def test_adds():
    assert 1 + 1 == 2
PY
git add pyproject.toml tests/test_math.py
git commit -q -m "seed"
