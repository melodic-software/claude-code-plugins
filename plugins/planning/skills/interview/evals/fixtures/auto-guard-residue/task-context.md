# Task context — idempotency keys on `POST /charges` (eval fixture)

The task as stated, plus the surrounding context. Raw material only: it does not sort the open items
into facts and decisions, and it does not say what the interview should do with any of them.

## What the user said

> Add idempotency keys to `POST /charges` in the payments service. Clients retry on network
> timeouts and we've double-charged twice this quarter. Follow whatever we already do elsewhere.

## What the endpoint does today

`POST /charges` accepts `{ account_id, amount_cents, currency, description }`, calls the processor,
writes a `charges` row, and returns `201` with the charge. There is no de-duplication of any kind.

## What "follow whatever we already do elsewhere" could reach

The webhooks module is the only part of the service that has ever handled a repeated request. See
`codebase-survey.md` for what it does and does not settle.

## Open items nobody has spoken to

Each item lists the shapes it could take. The list is not ordered by anything, and no item is
marked as settled or unsettled.

1. Which request header carries the key.
   - `Idempotency-Key`. The spelling used by the Stripe-style convention most client SDKs assume.
   - `X-Request-Id`. The spelling used by the internal gateway's tracing header.
2. Where a key and its outcome are stored.
   - A dedicated table keyed on the key value.
   - The `charges` row itself, with the key as a nullable unique column.
3. How long a stored key stays valid.
   - A fixed window, swept on a schedule.
   - Forever, with the row deleted only when the charge is.
4. What body a caller gets back when a key is rejected.
   - The service's standard error envelope.
   - A bare status code with no body.
5. What happens on a seen key with a body that does not match the stored request.
   - Replay the stored response. A retry that re-serialized its payload still gets through.
   - Reject the mismatch with a conflict. Two different charges under one key are refused.
