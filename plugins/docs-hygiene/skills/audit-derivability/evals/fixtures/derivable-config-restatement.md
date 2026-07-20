# Service runtime settings

The billing service listens on port `8080`. Its request timeout is `30s` and it
retries failed upstream calls `3` times before giving up. The health-check
endpoint is `/healthz` and readiness is `/readyz`.

Environment variables:

- `BILLING_DB_URL` — the Postgres connection string.
- `BILLING_LOG_LEVEL` — one of `debug`, `info`, `warn`, `error`.

The container image is built from `Dockerfile` at the repository root and the
service is deployed by `deploy/billing.yaml`.
