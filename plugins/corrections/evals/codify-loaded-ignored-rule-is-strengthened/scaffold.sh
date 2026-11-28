#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
printf '# Agents\n\n- Ask before building on a design choice the person has not approved.\n' >AGENTS.md
git add AGENTS.md
git commit -q -m "docs: add agent rules"
