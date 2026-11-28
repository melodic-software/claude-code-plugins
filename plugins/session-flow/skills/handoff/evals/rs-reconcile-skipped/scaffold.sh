#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf '.work/\n' >.gitignore
mkdir -p docs
printf '# Setup\n' >docs/setup.md
printf '# Usage\n' >docs/usage.md
git add -A
git commit -q -m "chore: starting point"
mkdir -p .work
printf '*\n' >.work/.gitignore
cp -R "$here/fixtures/handoffs" .work/handoffs
