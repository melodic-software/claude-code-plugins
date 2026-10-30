# Paved paths

| Concern | Chosen way | Enforced by |
|---|---|---|
| Scheduled jobs | A module under `jobs/` that exports a `Job`, listed in `jobs/registry.ts`, its `run` wrapped in `withRetry` from `jobs/retry.ts`. `jobs/cleanup-sessions.ts` shows it. | `tests/jobs-registry.test.ts` |
| Outbound email | `sendMail` from `lib/mailer.ts`. | none |
