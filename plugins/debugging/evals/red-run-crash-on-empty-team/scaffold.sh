#!/usr/bin/env bash
# A weekly hours report that divides by the entry count, so a team with no entries crashes it.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p data

cat > report.py <<'PY'
import json
import sys


def average_hours(entries):
    return sum(entry["hours"] for entry in entries) / len(entries)


def main(path):
    with open(path) as handle:
        teams = json.load(handle)
    for team, entries in teams.items():
        print("%s: %.1f h avg" % (team, average_hours(entries)))


if __name__ == "__main__":
    main(sys.argv[1])
PY

cat > data/week.json <<'JSON'
{"platform": [{"hours": 6}, {"hours": 8}], "design": []}
JSON

git add .
git commit -q -m "feat: weekly hours report"
