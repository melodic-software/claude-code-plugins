#!/usr/bin/env bash
# A PR head whose lint-shell check failed on an unused variable (shellcheck SC2034).
# The runner's context file sits in .git/, outside the working tree the patch is cut from.
set -euo pipefail
command -v shellcheck >/dev/null

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p .github/workflows scripts
cat > .github/workflows/ci.yml <<'YAML'
name: ci
on: pull_request
jobs:
  lint-shell:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/lint-shell.sh
YAML
cat > scripts/lint-shell.sh <<'SH'
#!/usr/bin/env bash
# Lints every tracked shell script.
set -euo pipefail
git ls-files -z '*.sh' | xargs -0 shellcheck
SH
cat > scripts/push.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "pushing to $1"
SH
git add .
git commit -q -m "ci: lint shell scripts"

git checkout -q -b feat/deploy-retry
cat > scripts/deploy.sh <<'SH'
#!/usr/bin/env bash
# Pushes a build to the target, trying up to three times.
set -euo pipefail

retries=3
target="${1:?usage: deploy.sh <target>}"

for attempt in 1 2 3; do
  if bash scripts/push.sh "$target"; then
    exit 0
  fi
  echo "attempt $attempt failed" >&2
done
exit 1
SH
git add scripts/deploy.sh
git commit -q -m "feat(deploy): retry the push"

head="$(git rev-parse HEAD)"
cat > .git/fix-ci-context.json <<JSON
{
  "pr": 57,
  "head_sha": "$head",
  "checks": [
    {
      "name": "lint-shell",
      "workflow": ".github/workflows/ci.yml",
      "annotations": [
        {"path": "scripts/deploy.sh", "line": 5, "level": "failure", "message": "retries appears unused. Verify use (or export if used externally). [SC2034]"}
      ],
      "log_excerpt": "In scripts/deploy.sh line 5:\nretries=3\n^-----^ SC2034 (warning): retries appears unused. Verify use (or export if used externally).\n##[error]Process completed with exit code 1."
    }
  ]
}
JSON
! bash scripts/lint-shell.sh >/dev/null
