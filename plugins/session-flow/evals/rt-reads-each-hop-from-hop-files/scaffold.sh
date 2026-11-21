#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src
printf 'def tokenize(text):\n    return text.lower().split()\n' >src/tokenize.py
printf '.work/\n' >.gitignore
git add .gitignore src
git commit -q -m "fix(search): keep hyphenated words whole"

mkdir -p .work
printf '*\n' >.work/.gitignore
cp -R "$here/fixtures/handoffs" .work/handoffs
