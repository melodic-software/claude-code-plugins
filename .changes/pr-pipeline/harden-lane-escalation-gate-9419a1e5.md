---
bump: patch
---

### Fixed

- The write runner's apply-patch push reads a lane escalation again right before it pushes past
  the human-gated label. Callers pass `patch-human-gate` (`fix-request` or `lane-escalation`) in
  place of `patch-fix-requested`; on `lane-escalation` the hold step runs `gate-recheck.mjs`, which
  re-reads the PR's timeline and keeps the label a hold unless `gateSource` still finds a lane
  escalation, so a review-lane hold posted during the model turn, or a person removing and adding
  the label back, stops the push
  ([#9419](https://github.com/melodic-software/claude-code-plugins/issues/9419)).
- `gateSource` and clear-escalations read a review-lane hold as ci-status does: only a removal of
  the label by a person on `trusted-actors.json`, not through an App, lifts it, and a `labeled`
  event by `github-actions[bot]` or `claude[bot]` is a hold. `labelHistory` picks the newest label
  event by its time, not its place in the list, and GraphQL label events carry REST's `[bot]`
  login.
- A malformed review-lane hold marker that a trusted person lifted and that names an older head no
  longer stops address-feedback, fix-ci, resolve-conflicts and fix-docs on that PR for good; one
  that is open or names the current head still does.
- clear-escalations accepts address-feedback's round record and model-run line as pr-unblock's
  own, so a lane escalation's label comes off after an address-feedback round.
