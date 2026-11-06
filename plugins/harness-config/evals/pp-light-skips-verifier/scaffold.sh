#!/usr/bin/env bash
# The quay repo with three project skills, one of them destructive with no gate, whose default
# branch sets verification: light for the harness-config plugin.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" postures
mkdir -p docs/conventions
printf '.work/\n' >>.gitignore
printf 'verification: light\n' >docs/conventions/harness-config.yaml
git add -A
git commit -q -m "chore: set the verification level"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
