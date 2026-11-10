#!/usr/bin/env bash
# A git repository with no team layer, so apply creates docs/conventions/user-interface.yaml.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/scaffold-guard.sh" docs README.md
git init -q -b main .
mkdir -p docs
printf '# App\n' >README.md
git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm seed
