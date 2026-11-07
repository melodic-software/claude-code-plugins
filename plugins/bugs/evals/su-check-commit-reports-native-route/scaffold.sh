#!/usr/bin/env bash
# A git repository whose AGENTS.md names docs/agent-reports/ as the home for agent-written reports,
# with one report already there. No bugs config at any layer.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" .git AGENTS.md docs src
git init -q
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src docs/agent-reports
printf 'export const ping = () => "pong";\n' >src/ping.ts
cat >AGENTS.md <<'MD'
# Service

Agent-written reports (reviews, audits, bug reports) are committed under `docs/agent-reports/`,
one Markdown file per report, so teammates see them in review.
MD
printf '# 2026-10-30 dependency audit\n\nNo findings.\n' >docs/agent-reports/2026-10-30-dependency-audit.md
git add -A
git commit -q -m "chore: initial commit"
