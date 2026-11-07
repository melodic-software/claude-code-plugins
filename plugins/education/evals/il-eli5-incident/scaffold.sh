#!/usr/bin/env bash
# Seeds an incident writeup and its log, so an ELI5 illustrate can run the incident grounding pass.
set -euo pipefail

mkdir -p incidents logs
cat >incidents/2026-10-29-checkout-outage.md <<'EOF'
# Checkout outage, Thursday 2026-10-29

Impact: 46 minutes in which most checkouts failed with a timeout.

- 14:02 A config deploy to payments-api changed PAYMENTS_DB_POOL_MAX from 50 to 5.
- 14:10 Lunchtime traffic rose. Every payments-api request waits in acquireConnection() for one of
  the 5 database connections.
- 14:12 checkout-web calls to payments-api start timing out after 30 seconds; checkout-web retries
  each failed call twice, which adds more waiting requests.
- 14:41 The config deploy is rolled back to a pool of 50.
- 14:48 The queue drains and checkouts succeed again.

Follow-up: the config schema now rejects a pool size under 20.
EOF
cat >logs/checkout-2026-10-29.log <<'EOF'
14:02:07 deploy payments-api config v412 PAYMENTS_DB_POOL_MAX=5 (was 50)
14:10:31 payments-api WARN acquireConnection waited 4.8s pool=5/5 waiting=37
14:12:02 checkout-web ERROR POST /payments timeout after 30000ms attempt=1
14:12:32 checkout-web ERROR POST /payments timeout after 30000ms attempt=2
14:13:02 checkout-web ERROR POST /payments timeout after 30000ms attempt=3 giving up
14:25:44 payments-api WARN acquireConnection waited 29.6s pool=5/5 waiting=412
14:41:15 deploy payments-api config v411 PAYMENTS_DB_POOL_MAX=50 (rollback)
14:48:09 payments-api INFO acquireConnection waited 0.01s pool=12/50 waiting=0
EOF
