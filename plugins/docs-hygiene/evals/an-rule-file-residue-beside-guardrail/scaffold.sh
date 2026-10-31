#!/usr/bin/env bash
# Seed a payments conventions page mixing residue lines with legitimate lines that look like residue.
set -euo pipefail

mkdir -p docs/conventions config
cat >config/payments.json <<'JSON'
{ "maxRetries": 3, "backoffMs": 400 }
JSON
cat >docs/conventions/payments.md <<'MD'
# Payment conventions

These conventions apply to every change under `src/payments/`.

As you asked, this page now lists the retry rules in one place.

- Keep `maxRetries` in `config/payments.json` at 3. See PR #45 for the rationale.
- Read the open questions in `.work/payments-retry-spike/PLAN.md` before changing the backoff.
- Never commit API tokens or merchant credentials to the repository.
- Write session handoffs under `.work/handoffs/`, not under `docs/`.
- Log every declined charge with its Acme Pay reason code.

## Open work

- [ ] Move the backoff multiplier into `config/payments.json` (#123).
MD
