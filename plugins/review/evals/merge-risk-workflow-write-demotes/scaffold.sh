#!/usr/bin/env bash
# main has a release workflow whose token can only read the repository. The branch adds a
# tag step and widens the job's permissions to contents: write, which meets the rubric's
# HIGH impact floor (a change that widens what an automated actor may do).
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p .github/workflows

cat >package.json <<'JSON'
{ "name": "storefront", "version": "1.4.0", "private": true, "scripts": { "build": "node build.js" } }
JSON

cat >.github/workflows/release.yml <<'YAML'
name: release
on:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npm run build
YAML

git add .
git commit -q -m "ci: build releases on main"
BASE=$(git rev-parse HEAD)

git checkout -q -b ci/87-tag-releases
cat >.github/workflows/release.yml <<'YAML'
name: release
on:
  push:
    branches: [main]
permissions:
  contents: write
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npm run build
      - name: Tag the release
        run: |
          version=$(node -p "require('./package.json').version")
          git tag "v$version"
          git push origin "v$version"
YAML

git add .
git commit -q -m "ci(release): tag each green release

Closes #87"
HEAD_OID=$(git rev-parse HEAD)

mkdir -p .claude-lane/pr
git diff main...HEAD >.claude-lane/pr/pr.diff
cp "$(dirname "${BASH_SOURCE[0]}")/fixtures/issue.md" .claude-lane/pr/issue.md

cat >.claude-lane/pr/facts.json <<JSON
{
  "number": 88,
  "url": "https://github.com/acme/storefront/pull/88",
  "state": "OPEN",
  "isDraft": false,
  "title": "ci(release): tag each green release",
  "body": "Closes #87\n\n## Summary\n\nThe release job now pushes a version tag after a green build.\n\n## Verification\n\nRan the workflow on a fork; the tag v1.4.0 appeared.",
  "baseRefName": "main",
  "headRefName": "ci/87-tag-releases",
  "baseRefOid": "$BASE",
  "headRefOid": "$HEAD_OID",
  "files": [{ "path": ".github/workflows/release.yml", "additions": 6, "deletions": 1 }],
  "labels": [],
  "visibility": "PUBLIC"
}
JSON
