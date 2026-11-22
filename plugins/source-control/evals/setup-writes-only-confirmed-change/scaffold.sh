#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf 'docs/conventions/**/*.local.*\n' > .gitignore
printf '# demo\n' > README.md
git add .gitignore README.md
git commit -q -m "WEB-101: seed"
