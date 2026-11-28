#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf '.work/\n' >.gitignore
printf '# Changelog\n\n## 1.4.0\n\n- Added: retry jitter.\n' >CHANGELOG.md
git add -A
git commit -q -m "chore: starting point"
mkdir -p .work
printf '*\n' >.work/.gitignore
cp -R "$here/fixtures/handoffs" .work/handoffs
