---
bump: minor
---

### Changed

- The intake, pr-unblock and pr-verify lanes run on their own funding roles' secrets instead of the `automations` pair. `intake-triage.yml` passes `role: intake` with `INTAKE_CLAUDE_API_KEY` and `INTAKE_CLAUDE_CODE_OAUTH_TOKEN`, and its intake reusable pins ci-workflows [`b0ecc27`](https://github.com/melodic-software/ci-workflows/commit/b0ecc273abe492d12f2efa98ee4741a84c219ed2), whose runner-policy contract names that role ([standards#863](https://github.com/melodic-software/standards/pull/863)). Every Claude job in `pr-unblock.yml` and the fix-docs jobs in `pr-refine.yml` pass `role: pr-unblock` with `PR_UNBLOCK_*`, and both `pr-verify.yml` jobs pass `role: pr-verify` with `PR_VERIFY_*`. Each run's `credential=` now names its own role's secret. `.github/lane-funding.json` lists the new secrets, the read-run secret allowlist in `scripts/check-read-caller-keys.mjs` admits `PR_UNBLOCK_*` in place of `AUTOMATIONS_*`, and `callers.test.mjs` fails when a catalog lane reads another role's secret or passes a `role:` other than its own ([pr-pipeline README, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding)).
