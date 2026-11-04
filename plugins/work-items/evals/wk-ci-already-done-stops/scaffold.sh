#!/usr/bin/env bash
# A checkout whose second commit already fixed what the issue asks for.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

printf 'scratch/\n' >.gitignore
mkdir -p docs scratch
printf '# Setup\n\nInstall with:\n\n    pip install widgit\n' >docs/setup.md # spellchecker:disable-line
git add .
git commit -q -m "docs: add the setup page"

printf '# Setup\n\nInstall with:\n\n    pip install widget\n' >docs/setup.md
git add docs/setup.md
git commit -q -m "fix(docs): correct the package name in the install command"

cat >scratch/issue.json <<'JSON'
{
  "number": 830,
  "title": "Fix the misspelled package name in the install command",
  "body": "The install command in docs/setup.md names the wrong package; the package is `widget`.\n\n## Done when\n\n- [ ] docs/setup.md shows `pip install widget`.\n",
  "labels": ["agent-ready"],
  "comments": []
}
JSON
