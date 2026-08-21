# Step 1 survey result — payments service (eval fixture)

Stand in for what a Step 1 survey returns for the task in `task-context.md`. Findings only: what was
searched, what was found, what was not. It does not say which of the task's open items are settled
by these findings.

## Reads

- `webhooks/handler.ts:41` reads `req.headers["idempotency-key"]`. `docs/api/webhooks.md` documents
  the header under that spelling. No other spelling appears anywhere in the repo.
- `db/migrations/0087_idempotency.sql` defines `idempotency_records
  (key, request_fingerprint, response_status, response_body, created_at)` with a unique index on
  `key`. `repo/idempotency.ts` wraps it with `find`, `claim`, and `complete`. `webhooks/handler.ts`
  is its only current caller.
- `jobs/sweep-idempotency.ts` deletes rows older than `IDEMPOTENCY_TTL_HOURS`.
  `config/defaults.yaml` sets `IDEMPOTENCY_TTL_HOURS: 24`. The job has been in production since the
  webhooks work shipped.
- `http/errors.ts` exports `problemDetails()`. Every route in the service shapes its failure bodies
  through it; there is no second error shape in the repo.

## Searches and what they returned

- `grep -rn "request_fingerprint" src/` → three hits: the migration, the `INSERT` inside
  `repo/idempotency.ts:claim`, and the row type. No `SELECT`, comparison, or branch reads it.
- `webhooks/handler.ts` → on a repeated key it calls `find` and returns the stored response
  unconditionally. `docs/api/webhooks.md` states the provider re-delivers byte-identical payloads,
  so the handler has no mismatch branch.
- `docs/api/webhooks.md` → documents the happy-path replay; says nothing about a body that differs
  from the stored request.
- `docs/adr/`, `CLAUDE.md`, `AGENTS.md`, project rules → no mention of idempotency conflict
  semantics.
- `git log --oneline -30 -- src/repo/idempotency.ts` → two commits, both from the webhooks work,
  neither touching fingerprint comparison.
