#!/usr/bin/env bash
# Seeds a fully answered interview Brief whose rate-limit answer contradicts its own constraint.
set -euo pipefail

slice=.work/export-rate-limit
mkdir -p "$slice" docs
cat >"$slice/PLAN.md" <<'MD'
# Export API rate limiting

## Brief

**Goal:** Rate-limit the `/v2/exports` endpoint per API key so one tenant cannot starve the others.

**Constraints:**

- Bulk sync clients are contractually allowed 20 requests per second per API key (docs/sla.md).
- No new infrastructure this quarter.

**Acceptance criteria:**

- A key over its limit gets a rejection the client can back off from.
- Keys under the limit see no added latency above 5 ms at p99.

### Resolved decisions

- **D1. Counter store:** the existing Redis cluster that already holds sessions.
  *Why (recommendation):* zero extra ops burden because the platform team already babysits the session Redis.
- **D2. Limit value:** 600 requests per minute per API key, fixed window.
  *Why (recommendation):* matches the busiest customer's traffic at p99 with headroom.
- **D3. Over-limit response:** HTTP 429 with a `Retry-After` header.
  *Why (recommendation):* the Stripe convention our SDK users already expect.

### Deferred questions

- **Q4. Should enterprise-tier keys be exempt from the limit?** USER-RESERVED (arbiter: product owner)
MD
cat >docs/sla.md <<'MD'
# Export API service levels

Bulk sync clients may call `/v2/exports` at up to 20 requests per second per API key, sustained.
MD
