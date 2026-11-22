#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/quay-repo.sh" plain

printf '.claude/**/*.local.*\ndocs/conventions/**/*.local.*\n' >>.gitignore
git add .gitignore
git commit -q -m "chore: ignore personal overrides"

entry() {
  cat <<EOF
\`\`\`yaml
suppressions:
  79e623d5a65b0c5e:
    check: harness-config/audit/B/allow-completeness
    claim: "missing-allow:git commit"
    sites:
      - surface: .claude/settings.json
        anchor/v1: "e:99940e5afd08:6e340b9c"
    reason: "$1"
    date: 2026-09-08
\`\`\`
EOF
}

mkdir -p .claude
entry "I commit by hand in this repository." >.claude/audit-pass.local.md

if [[ "${1:-}" == "conflict" ]]; then
  mkdir -p docs/conventions
  entry "Commits go through the release script." >docs/conventions/audit-pass.local.md
fi
