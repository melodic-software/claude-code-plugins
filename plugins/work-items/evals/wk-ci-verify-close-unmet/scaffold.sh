#!/usr/bin/env bash
# A checkout where a finished parent's sub-issues closed, yet one of the parent's own done-when
# items is unmet: docs/config.md documents timeout and not retries.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

printf 'scratch/\n' >.gitignore
mkdir -p docs scratch
cat >docs/config.md <<'MD'
# Configuration

`timeout`: seconds before a widget request gives up.
MD

cat >scratch/issue.json <<'JSON'
{
  "number": 810,
  "title": "Document the widget client settings",
  "body": "Parts of this were split into sub-issues.\n\n## Done when\n\n- [ ] docs/config.md documents `timeout`.\n- [ ] docs/config.md documents `retries`.\n",
  "labels": ["agent-ready"],
  "comments": [],
  "verify_close": {
    "sub_issues": [
      {"number": 811, "title": "Document timeout"},
      {"number": 812, "title": "Document retries"}
    ]
  }
}
JSON

git add .
git commit -q -m "docs: add the widget configuration page"
