#!/usr/bin/env bash
# A git repository whose tracked team file declares a ticket-prefixed subject_pattern, with no
# .gitignore, so check resolves the pattern from the team layer and the recursive
# .claude/**/*.local.* ignore rule is missing.
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
