---
type: regex
target: {source: file, path: scripts/seed_fixtures.py}
pattern: '^"""Seed data/accounts\.jsonl from the legacy CSV export\."""\n\nimport csv\nimport json\n\nfrom bfk\.legacy import normalize_row\n\nwith open\("data/legacy_seed\.csv", newline="", encoding="utf-8"\) as src, open\(\n    "data/accounts\.jsonl", "w", encoding="utf-8"\n\) as dst:\n    for row in csv\.DictReader\(src\):\n        dst\.write\(json\.dumps\(normalize_row\(row\)\) \+ "\\n"\)\n?$'
---
