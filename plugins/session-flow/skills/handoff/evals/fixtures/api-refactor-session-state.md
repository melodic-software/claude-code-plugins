# api-refactor: state of this session's work

Synthetic eval fixture. It stands in for the earlier part of the session a handoff summarizes.

## Goal, in the owner's words (2026-10-20)

> Replace the three ad-hoc order lookup endpoints with one versioned `GET /v2/orders` resource
> that the mobile and partner clients can both use, without breaking v1 callers this quarter.

## Done so far

- Read the three v1 handlers (`src/orders/byId.ts`, `src/orders/byCustomer.ts`,
  `src/orders/recent.ts`) and listed what each caller relies on.
- Drafted the v2 resource shape in `api-refactor-endpoint-design.md` (the draft the review
  will look at).
- Added `src/orders/v2/router.ts` with the route registered and a handler that returns
  `501 Not Implemented`. Committed as `feat(orders): register v2 orders route` on branch
  `feat/orders-v2`.

## Decisions made

- v1 endpoints stay untouched until v2 ships; they will forward to v2 later, not now.
- Responses use the existing error envelope (`{ "error": { "code", "message" } }`); no new
  error format.

## Uncommitted change

`src/orders/v2/query.ts` is half written: filter parsing for `customerId` and `status` works;
the `since` filter and the pagination cursor are stubbed with `TODO` and throw at runtime.

## Open questions (none decided yet)

- Pagination: opaque cursor (current draft) or page and page-size, which the partner client
  already uses on other endpoints.
- Auth scope: reuse `orders:read`, or add `orders:read:partner` so partners see only their own
  orders.
- Whether `GET /v2/orders/{id}` is a separate route or `?id=` on the collection.

## Remaining work (order not yet fixed)

- Write the migration adding an index on `orders(customer_id, created_at)`.
- Settle the pagination model with the platform team.
- Finish the `since` filter and cursor in `src/orders/v2/query.ts`.
- Settle the auth scope question with the platform team.
- Add handler tests for each filter.
- Decide the single-order route shape.
