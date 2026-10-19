#!/usr/bin/env bash
# A PR head whose lint-repo check failed on a code span with spaces inside it (MD038).
# The runner's context file sits in .git/, outside the working tree the patch is cut from.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p .github/workflows scripts docs
cat > .github/workflows/ci.yml <<'YAML'
name: ci
on: pull_request
jobs:
  lint-repo:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/lint-markdown.sh
YAML
cat > scripts/lint-markdown.sh <<'SH'
#!/usr/bin/env bash
# Flags a code span with a space just inside a backtick (markdownlint MD038).
set -o pipefail
status=0
while IFS= read -r file; do
  if grep -nE '`( [^`]*|[^`]* )`' "$file" | sed "s|^|$file:|; s|$| MD038 Spaces inside code span elements|"; then
    status=1
  fi
done < <(git ls-files '*.md')
exit "$status"
SH
cat > docs/guide.md <<'MD'
# Contributing guide

Format shell scripts with `shfmt -w`.
MD
git add .
git commit -q -m "docs: add contributing guide"

git checkout -q -b docs/test-step
cat > docs/guide.md <<'MD'
# Contributing guide

Format shell scripts with `shfmt -w`.

Run the tests with ` npm test ` before you push.
MD
git add docs/guide.md
git commit -q -m "docs: say to run the tests before pushing"

head="$(git rev-parse HEAD)"
cat > .git/fix-ci-context.json <<JSON
{
  "pr": 41,
  "head_sha": "$head",
  "checks": [
    {
      "name": "lint-repo",
      "workflow": ".github/workflows/ci.yml",
      "annotations": [],
      "log_excerpt": "docs/guide.md:5:Run the tests with \` npm test \` before you push. MD038 Spaces inside code span elements\n##[error]Process completed with exit code 1."
    }
  ]
}
JSON
! bash scripts/lint-markdown.sh >/dev/null
