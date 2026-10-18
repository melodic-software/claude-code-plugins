#!/usr/bin/env bash
# Seeds the eval workspace with a git repo that has no source-control config at any layer: one commit
# on main, and the recursive .claude/**/*.local.* ignore rule already in place so apply has no
# .gitignore edit of its own to make.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '.claude/**/*.local.*\n' > .gitignore
printf '# demo\n' > README.md
git add .gitignore README.md
git commit -q -m "WEB-101: seed"
