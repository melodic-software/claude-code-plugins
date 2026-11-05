#!/usr/bin/env bash
# A git repository with no multi-agent layer and no .gitignore, so the personal-override row is a WARN.
set -euo pipefail
git init -q -b main
git config core.excludesFile /dev/null
printf '# demo\n' >README.md
