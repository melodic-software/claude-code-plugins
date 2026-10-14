#!/usr/bin/env bash
# A main working tree (not a linked worktree) with the CSV export in progress and an unrelated
# uncommitted edit from another task, and no remote.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src tests
cat >src/export.py <<'EOF'
import csv


def write_header(handle, columns):
    csv.writer(handle).writerow(columns)
EOF
cat >src/other_feature.py <<'EOF'
def greeting(name):
    return "Hello, " + name
EOF
cat >tests/test_export.py <<'EOF'
import io

from src.export import write_header


def test_header():
    out = io.StringIO()
    write_header(out, ["id", "amount"])
    assert out.getvalue() == "id,amount\r\n"
EOF
printf '.work/\n__pycache__/\n' >.gitignore
git add .gitignore src tests
git commit -q -m "csv export header"

cat >src/other_feature.py <<'EOF'
def greeting(name, punctuation="!"):
    return "Hello, " + name + punctuation
EOF
