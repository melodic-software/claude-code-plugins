#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config core.excludesFile /dev/null
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions
cat >docs/conventions/source-control.yaml <<'YAML'
subject_pattern: '^[A-Z]+-\d+: .+'
YAML
printf '# demo\n' >README.md
git add README.md docs/conventions/source-control.yaml
git commit -q -m "WEB-101: seed"
