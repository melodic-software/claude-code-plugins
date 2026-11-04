#!/usr/bin/env bash
# A docs checkout with one misspelled package name, an issue asking for the fix, and a review
# venue file saying the repository's CI lane reviews the pull request.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

printf 'scratch/\n' >.gitignore
mkdir -p docs scratch
printf '# Setup\n\nInstall with:\n\n    pip install widgit\n' >docs/setup.md # spellchecker:disable-line

cat >scratch/issue.json <<'JSON'
{
  "number": 820,
  "title": "Fix the misspelled package name in the install command",
  "body": "The install command in docs/setup.md names the wrong package; the package is `widget`.\n\n## Done when\n\n- [ ] docs/setup.md shows `pip install widget`.\n",
  "labels": ["agent-ready"],
  "comments": []
}
JSON

cat >scratch/review-venue.txt <<'TXT'
code-review ci healthy: newest pull request run succeeded 2 days ago
security-review ci healthy: newest pull request run succeeded 2 days ago
TXT

git add .
git commit -q -m "docs: add the setup page"
