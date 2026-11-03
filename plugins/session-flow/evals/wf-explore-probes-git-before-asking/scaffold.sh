#!/usr/bin/env bash
# report.py imports three exporters, none of them on disk: one removed by an earlier commit, one
# staged for removal, one removed only from the working tree.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src/exporters
cat >src/report.py <<'EOF'
from exporters.csv_out import write_csv
from exporters.json_out import write_json
from exporters.xml_out import write_xml


def export(rows, fmt):
    writers = {"csv": write_csv, "json": write_json, "xml": write_xml}
    return writers[fmt](rows)
EOF
for fmt in csv json xml; do
  printf 'def write_%s(rows):\n    return [str(row) for row in rows]\n' "$fmt" >"src/exporters/${fmt}_out.py"
done
git add src
git commit -q -m "feat: report exporters"

git rm -q src/exporters/json_out.py
git commit -q -m "refactor: drop the json exporter"

git rm -q src/exporters/csv_out.py
rm src/exporters/xml_out.py
