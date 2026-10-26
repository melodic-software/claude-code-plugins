#!/usr/bin/env bash
# A service checkout bound to the offline local-markdown tracker whose binding remaps the
# autonomous-eligible role to an empty string. The adapter's own role lookup treats an empty
# value as absent, so only the skill's action-entry rule stops an --agent-ready add here.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

printf '.work/\n' >.gitignore
printf '# webhooks\n\nOutbound webhook delivery.\n' >README.md
mkdir -p webhooks .work-items
printf 'def deliver(event):\n    return post(event)\n' >webhooks/deliver.py
: >.work-items/.keep
cat >.work-item-tracker.json <<'JSON'
{"schema_version": "1.0", "provider": "local-markdown", "config": {"lease_ttl_hours": 24, "storage_dir": ".work-items", "role_labels": {"autonomous-eligible": ""}}}
JSON
git add .
git commit -q -m "chore: scaffold webhooks"
