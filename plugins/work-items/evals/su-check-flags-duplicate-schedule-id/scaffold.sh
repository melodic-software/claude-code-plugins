#!/usr/bin/env bash
# A bound checkout (local-markdown binding in docs/conventions/work-items.yaml) whose tracked
# recurring schedule carries two rows with the same id but different titles.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p docs/conventions .github .work-items
printf '%s\n' \
  'tracker:' \
  '  schema_version: "1.0"' \
  '  provider: local-markdown' \
  '  docs: Work-item tracker binding, see the work-items plugin tools/work-item-tracker/CONTRACT.md (Setup)' \
  '  config:' \
  '    lease_ttl_hours: 24' \
  '    storage_dir: .work-items' >docs/conventions/work-items.yaml

printf '%s\n' \
  '.work/' \
  'docs/conventions/work-items.local.yaml' >.gitignore

cat >.github/recurring-schedule.json <<'JSON'
{
  "items": [
    {
      "id": "dependency-review",
      "title": "Review dependency manifest",
      "cadence": "quarterly",
      "area": ["build"],
      "category": "maintenance",
      "triggers": [],
      "notes": "",
      "close_previous": true,
      "last_checked": "2026-09-01",
      "next_due": "2026-12-01"
    },
    {
      "id": "dependency-review",
      "title": "Review CI workflow pins",
      "cadence": "quarterly",
      "area": ["ci"],
      "category": "maintenance",
      "triggers": [],
      "notes": "",
      "close_previous": true,
      "last_checked": "2026-09-01",
      "next_due": "2026-12-01"
    }
  ]
}
JSON

printf '# widget\n\nA small widget library.\n' >README.md
touch .work-items/.gitkeep
git add .
git commit -q -m "chore: scaffold widget"
