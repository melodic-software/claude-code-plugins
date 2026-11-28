#!/usr/bin/env bash
set -euo pipefail

mkdir -p config docs/adr docs/blog docs/contracts docs/ops

cat >README.md <<'EOF'
# ledger-sync

`ledger-sync` delivers signed webhook notifications when ledger batches settle.

## Retry behavior

Failed webhook deliveries retry with exponential backoff capped at 300 seconds (`max_backoff_seconds: 300`) using `equal` jitter (`jitter_mode: equal`).

For background and operational details, see `docs/adr/0004-webhook-retries.md` and `docs/ops/runbook-webhooks.md`.
EOF

cat >config/legacy-defaults.yaml <<'EOF'
schema_version: 1
status: deprecated
note: "Retained only for v1 replay tests; ignored by the current delivery daemon."
webhook_delivery:
  max_backoff_seconds: 300
  jitter_mode: equal
  max_attempts: 8
EOF

cat >docs/adr/0004-webhook-retries.md <<'EOF'
# ADR 0004: Webhook delivery retry policy

- Status: Superseded by `docs/contracts/webhook-delivery.md` (rev 3)
- Date: 2023-09-12

## Decision

Webhook deliveries retry with exponential backoff capped at 300 seconds (`max_backoff_seconds: 300`) and `equal` jitter (`jitter_mode: equal`).

## Appendix (2024-01)

An experimental 180-second cap was tested in staging and abandoned before the normative contract was written.
EOF

cat >docs/blog/2024-06-retry-tuning.md <<'EOF'
# Tuning webhook retries under bursty load

- Status: Informative (non-normative engineering note)
- Date: 2024-06-18

In a load-test prototype we raised `max_backoff_seconds` to `600` and switched `jitter_mode` to `full` to smooth downstream spikes. That prototype was never adopted as the production contract.
EOF

cat >docs/ops/runbook-webhooks.md <<'EOF'
# Webhook operations runbook

Last reviewed: 2024-02-05

## Expected retry ceiling

Per ADR 0004, webhook retries cap at `max_backoff_seconds: 300` with `jitter_mode: equal`. Check `config/legacy-defaults.yaml` if a test environment overrides these values.
EOF

cat >docs/contracts/webhook-delivery.md <<'EOF'
# Webhook Delivery Contract (rev 3)

- Status: Normative (Authoritative)
- Effective: 2025-04-01

## Precedence

This contract is the single authoritative source of truth for webhook delivery retry behavior in `ledger-sync`. It supersedes `README.md`, `docs/adr/0004-webhook-retries.md`, `docs/blog/2024-06-retry-tuning.md`, `docs/ops/runbook-webhooks.md`, and `config/legacy-defaults.yaml`.

## Required retry parameters

All delivery workers MUST enforce:

- `max_backoff_seconds`: `90`
- `jitter_mode`: `decorrelated`
- `initial_backoff_seconds`: `2`
- `max_attempts`: `10`
EOF
