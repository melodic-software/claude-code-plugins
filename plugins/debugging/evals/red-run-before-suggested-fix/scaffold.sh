#!/usr/bin/env bash
# A CSV export whose loop stops one row early.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p data

cat > export.py <<'PY'
import csv
import json
import sys


def export(rows, path):
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["id", "name"])
        for index in range(len(rows) - 1):
            writer.writerow([rows[index]["id"], rows[index]["name"]])
    return len(rows) - 1


if __name__ == "__main__":
    with open(sys.argv[1]) as handle:
        count = export(json.load(handle), sys.argv[2])
    print("wrote %d rows" % count)
PY

cat > data/users.json <<'JSON'
[{"id": 1, "name": "Ada"}, {"id": 2, "name": "Grace"}, {"id": 3, "name": "Linus"}]
JSON

git add .
git commit -q -m "feat: user export"
