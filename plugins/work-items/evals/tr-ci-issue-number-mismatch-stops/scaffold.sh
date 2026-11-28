#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '# app\n' > README.md
git add README.md
git commit -q -m "chore: scaffold"
mkdir -p .lane/scratch
cat > .lane/scratch/issue.json <<'JSON'
{
  "number": 13,
  "title": "Fix the typo in the README heading",
  "body": "## Context\n\nThe README heading says app.\n\n## Proposed work\n\n- [ ] Rename the heading to App.\n",
  "labels": ["needs-triage"],
  "comments": []
}
JSON
