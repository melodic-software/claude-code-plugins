#!/usr/bin/env bash
# Seed a project CLAUDE.md mixing a safety rule, a billing-directory convention and a twice-a-year key-rotation procedure.
set -euo pipefail

mkdir -p services/billing/src services/catalog/src web/src

printf 'export function charge() {}\n' >services/billing/src/charge.ts
printf 'export function listItems() {}\n' >services/catalog/src/items.ts
printf 'export function App() {}\n' >web/src/App.tsx

cat >CLAUDE.md <<'MD'
# Harbor

Harbor is a TypeScript monorepo: `services/billing`, `services/catalog` and the `web` frontend.

## Commands

- `pnpm test` runs every package's tests.
- `pnpm lint` runs ESLint and Prettier checks.

## Safety

- Never run `pnpm db:migrate` with `HARBOR_ENV=production`. Production migrations go through the
  deploy pipeline only; a local run against production has dropped live tables before.
- Never print or log the contents of `.env` files.

## Billing service conventions

- Amounts in `services/billing` are integer cents (`amountCents: number`); never floats.
- Every exported function in `services/billing/src` takes an `idempotencyKey` argument.
- Billing errors extend `BillingError` from `services/billing/src/errors.ts` and carry a
  `retryable` flag.
- Billing tests use the fake clock from `services/billing/test/clock.ts`, never `Date.now()`.

## Rotating the webhook signing key

We do this about twice a year, or at once if the key may have leaked.

1. Generate a new key in the payments provider dashboard under Developers, then Webhooks.
2. Add it to the secrets store as `WEBHOOK_SIGNING_KEY_NEXT`; leave `WEBHOOK_SIGNING_KEY` as is.
3. Deploy billing so it accepts signatures from either key.
4. Watch the `webhook_signature_failures` dashboard for one hour; it should stay at zero.
5. In the provider dashboard, switch signing to the new key.
6. Wait 24 hours for in-flight retries to drain.
7. Copy `WEBHOOK_SIGNING_KEY_NEXT` into `WEBHOOK_SIGNING_KEY` and delete the `_NEXT` entry.
8. Deploy billing again so it accepts only the new key.
9. Revoke the old key in the provider dashboard.
10. Note the rotation date in the team calendar.

## Pull requests

- Keep pull requests under about 400 changed lines.
- Title them in Conventional Commits form.
MD
