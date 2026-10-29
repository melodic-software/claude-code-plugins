---
bump: minor
---

### Added

- A lanes App pull request that holds for a person carries the `human-merge-hold` label as well as
  the `Hold: a human merges this` body line, which the App can edit
  ([#9437](https://github.com/melodic-software/claude-code-plugins/issues/9437)). report-outcome
  adds the label right after it opens the pull request, or when it reuses its open one; a pull
  request the label cannot reach is closed and the issue retried (`hold-label-failed`). ci-status's
  new `Fail a human-merge hold a listed person has not lifted` step fails while the label is on,
  and once it is off unless the first removal at or after its newest add was by a `human` of the
  base's trusted-actor list acting directly, not through an App. `enable-auto-merge.mjs`
  (`HOLD_LABELS`) never arms a pull request carrying it, and merge-holds.mjs `labelHolds` holds it
  in the merge queue, so deleting the hold line or rewriting `Refs: #N` to `Closes #N` no longer
  lets a held pull request merge.
