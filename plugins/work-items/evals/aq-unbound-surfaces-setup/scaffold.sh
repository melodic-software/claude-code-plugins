#!/usr/bin/env bash
# A checkout with no tracker binding (no docs/conventions/work-items.yaml) and no remote: the attended queue has
# no seam to claim rows through and no forge to read.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

printf '.work/\n' >.gitignore
printf '# widget\n\nA small widget library.\n' >README.md
git add .
git commit -q -m "chore: scaffold widget"
