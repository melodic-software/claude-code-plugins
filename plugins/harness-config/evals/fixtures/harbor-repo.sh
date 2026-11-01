#!/usr/bin/env bash
# Seeds a small TypeScript monorepo with Claude Code configuration and instruction surfaces:
# project settings with a blanket git allow, a hook whose script is missing and a millisecond
# timeout; a local settings file holding a deny rule and a webhook secret; an MCP server whose
# command does not resolve; a root CLAUDE.md; two project skills; and a nested CLAUDE.md under
# services/billing that contradicts the deploy skill. Pass --no-git to skip the repository.
set -euo pipefail

mkdir -p .claude/skills/release-notes .claude/skills/deploy services/billing/src web/src

printf '.claude/settings.local.json\nnode_modules/\n' >.gitignore
printf 'export function charge() {}\n' >services/billing/src/charge.ts
printf 'export function App() {}\n' >web/src/App.tsx
printf '{\n  "name": "harbor",\n  "private": true,\n  "scripts": {"test": "vitest run"}\n}\n' >package.json

cat >.claude/settings.json <<'JSON'
{
  "permissions": {
    "allow": ["Bash(git *)", "Bash(pnpm test)"],
    "deny": []
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/format-changed.sh",
            "timeout": 30000
          }
        ]
      }
    ]
  }
}
JSON

cat >.claude/settings.local.json <<'JSON'
{
  "permissions": {
    "deny": ["Bash(rm -rf:*)"]
  },
  "env": {
    "HARBOR_WEBHOOK_SECRET": "FAKE-HARBOR-WEBHOOK-VALUE"
  }
}
JSON

cat >.mcp.json <<'JSON'
{
  "mcpServers": {
    "orders-db": {
      "command": "harbor-orders-mcp",
      "args": ["--readonly"]
    }
  }
}
JSON

cat >CLAUDE.md <<'MD'
# Harbor

Harbor is a TypeScript monorepo: `services/billing` and the `web` frontend.

## Commands

- `pnpm test` runs every package's tests.
- `pnpm lint` runs ESLint and Prettier.

## Working here

- Never use default exports.
- Do not add dependencies.
- Before answering, think step by step and show your reasoning to the user.
MD

cat >.claude/skills/release-notes/SKILL.md <<'MD'
---
name: release-notes
description: Draft release notes for Harbor from merged pull requests. Use when asked for release notes or a changelog entry.
---

# Release notes

CRITICAL: You MUST ALWAYS use the Grep tool on the git log before writing anything. IMPORTANT: use this
skill EVERY time anyone mentions a release.

1. List the pull requests merged since the last tag.
2. Group them under Added, Changed and Fixed.
3. Write one line per change, in the past tense.

Be conservative: only report changes you are completely certain about.
MD

cat >.claude/skills/deploy/SKILL.md <<'MD'
---
name: deploy
description: Deploy a Harbor service to staging. Use when asked to deploy billing or web.
---

# Deploy

1. Confirm the branch is green in CI.
2. Always run `pnpm db:migrate` from `services/billing` before deploying billing.
3. Run `pnpm deploy --env staging` for the service.
MD

cat >services/billing/CLAUDE.md <<'MD'
# Billing service

- Amounts are integer cents (`amountCents: number`).
- Never run `pnpm db:migrate` in this package. Migrations run only through `make migrate` from the
  repository root.
MD

[[ "${1:-}" == "--no-git" ]] && exit 0

git init -q -b main
git config user.name harbor
git config user.email harbor@example.invalid
git add -A
git commit -q -m "chore: seed harbor"
