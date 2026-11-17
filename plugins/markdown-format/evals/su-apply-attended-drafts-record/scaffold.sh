#!/usr/bin/env bash
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.markdown-format.format.declined true
git config --local checks.markdown-format.lint.declined true
mkdir -p docs
printf '{\n  "name": "demo",\n  "private": true,\n  "devDependencies": {\n    "prettier": "3.3.3",\n    "remark-cli": "12.0.1",\n    "remark-preset-lint-recommended": "7.0.0"\n  }\n}\n' >package.json
printf '{\n  "proseWrap": "always"\n}\n' >.prettierrc
printf '{\n  "plugins": ["remark-preset-lint-recommended"]\n}\n' >.remarkrc.json
printf '# Guide\n\nSome text.\n' >docs/guide.md
git add .
git commit -q -m "chore: init"
