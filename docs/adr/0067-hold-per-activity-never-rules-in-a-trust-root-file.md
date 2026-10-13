# Hold per-activity never-rules in a trust-root file

- Status: accepted
- Date: 2026-10-12

## Context

What a lane may never do lived on its row in `lane-rules.json`, a trust-root file the config
reader applies. Once a lane holds several activities with different powers (pr-unblock's
`resolve-conflicts` writes the branch, its `report-escalation` only labels and comments), a
lane-wide rule is either too loose for the narrow activity or too tight for the wide one. Each
activity needs its own rule, and the rule has to sit where the config that defines the activity
cannot loosen it.

## Decision

Per-activity rules live in
[`.github/actions/resolve-config/activity-rules.json`](../../.github/actions/resolve-config/activity-rules.json),
beside `lane-rules.json` and `effect-grants.json`, keyed by leaf
([ADR 0066](0066-group-pipeline-activities-into-composites-with-effects-and-grants-on-leaves-only.md)):

1. Each row holds `never`, a statement of what the leaf never does, and optionally
   `forbidden-effects`, effects it may never be given. A leaf with no row is valid; a missing or
   malformed file is a config error, and every forbidden effect must be one `effect-grants.json`
   knows. Basis: [`resolve.mjs:169-196`](../../.github/actions/resolve-config/resolve.mjs).
2. The reader rejects a leaf whose `effect` its row forbids, as `forbidden-by-activity`. Today
   `report-escalation` may never be `mutate-branch` or `merge`. Basis: `resolve.mjs:198-221`;
   `activity-rules.json:5-8`.
3. The file is read from the action's own trusted checkout, never from the PR head, and the token
   broker reads it at the default-branch tip as one of its trust files. It is a trust-root path.
   Basis: [`resolve-config.mjs:34-35,184-192`](../../.github/actions/resolve-config/resolve-config.mjs);
   `melodic-software/azure-iac` `src/lanes-token-broker/src/binding.mjs:7-26`;
   [pr-pipeline README, "Trust-root paths"](../conventions/pr-pipeline/README.md#trust-root-paths).

## Alternatives considered

- **`never:` on the activity in `pr-pipeline.yaml`.** Rejected: a rule beside the definition it
  limits can be loosened in the same hunk that widens the activity. Under `.github/actions/**`,
  loosening the rule is a separate trust-root change from widening the activity. Basis: judgment,
  on the trust-root list in the pr-pipeline README (lines 311-340); the owner chose this option in
  the pr-unblock design review on 2026-10-11.
- **Keep rules per lane only.** Rejected: one lane now holds activities with different effects.
  Basis: [`pr-pipeline.yaml:16-39`](../conventions/pr-pipeline.yaml) (`mutate-branch` and
  `publish-artifact` in the pr-unblock lane).

## Consequences

- `forbidden-effects` is enforced by the reader. The `never` text is not machine-checked by the
  reader; for `resolve-conflicts` the write runner's structure test asserts each clause
  ([`scripts/write-runner-never-rules.test.sh`](../../scripts/write-runner-never-rules.test.sh)).
  That test cannot cover the skill's own tool grant, which its header names.
- A new leaf with no row passes; adding a row is a trust-root change.
