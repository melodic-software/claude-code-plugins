#!/usr/bin/env bash
# Seeds a repository whose CLAUDE.md is short on its own but imports a long guide,
# so the lines that load at launch pass the 200-line target only once the import is expanded.
set -euo pipefail

git init -q -b main
git config user.name dev
git config user.email dev@example.invalid

mkdir -p docs src
cat >CLAUDE.md <<'MD'
# Invoicing service

Billing backend for the shop: creates invoices, applies tax, and sends them to customers.

## Commands

- Build: `make build`
- Test: `make test`
- Lint: `make lint`

## Layout

- `src/` holds the service code, one folder per module.
- `docs/` holds the guides below.

## Working here

- Keep each change to one module where you can.
- Money is integer cents everywhere; never use floats for amounts.
- Run `make test` before you hand a change back.

Module notes: @docs/module-guide.md
MD

modules="ledger tax currency pdf email webhooks customers products discounts refunds credit-notes
reminders exports imports audit-log permissions api-keys rate-limits scheduler reports search
notifications settings invoices payments subscriptions plans coupons usage"
{
  echo "# Module guide"
  echo
  for m in $modules; do
    echo "## $m"
    echo
    echo "- Code lives in \`src/$m/\`; its tests sit beside it in \`src/$m/tests/\`."
    echo "- Owner: the billing team; ask in the team channel before changing its public API."
    echo "- Entry point: \`src/$m/index.ts\` exports the module's service object."
    echo "- Errors: throw the module's own error type, never a bare Error."
    echo "- Logging: use the shared logger with the \`$m\` tag."
    echo "- Config: read settings through \`src/settings\`, never from the environment directly."
    echo "- Migrations for \`$m\` go in \`src/$m/migrations/\`, one file per change."
    echo
  done
} >docs/module-guide.md

printf 'export {};\n' >src/index.ts

# A run's user scope is unreadable, so the auto-memory state the audit resolves is set here.
mkdir -p .claude
printf '{\n  "autoMemoryEnabled": false\n}\n' >.claude/settings.json

git add CLAUDE.md docs src .claude
git commit -q -m "chore: initial layout"
