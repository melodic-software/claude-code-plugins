#!/usr/bin/env bash
# Commits src/report.py with an existing private one-call wrapper, appends an uncommitted second one with its only caller, and writes the lines file naming lines 10-18, the appended block only.
set -euo pipefail

git init -q
git symbolic-ref HEAD refs/heads/main
mkdir -p src
cat >src/report.py <<'EOF'
from csvtools import read_csv_rows, read_json_rows


def _load_events(path):
    return read_json_rows(path)


def count_events(path):
    return len(_load_events(path))
EOF
git add src/report.py
git -c user.name=dev -c user.email=dev@example.invalid -c commit.gpgsign=false commit -q -m "add event count"
cat >>src/report.py <<'EOF'


def _load_rows(path):
    return read_csv_rows(path)


def summarize(path):
    rows = _load_rows(path)
    return len(rows)
EOF
printf '10\t9\tsrc/report.py\n' >changed-lines.tsv
