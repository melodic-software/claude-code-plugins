---
bump: minor
---

### Changed

- **The issue lane's `research-first` and `probe-first` skips reach no person.** They take a new `park` route in `stop-routes.json`: the lanes App writes admission's comment naming the next step, adds `status: confirmed`, and removes `agent-ready`, `status: ready` and `admission-deferred`, as admission parks the same refusal, so a listed human's `**Decision recorded.**` comment sends the issue back through intake. The lane comment carries an `outcome=parked` marker. `split-required` keeps its `intake` route to intake's size split (owner Q93). Admission's comment helpers moved to `.github/scripts/lib/admission-comment.mjs`, which admission and report-outcome share; the hold floor lists it as an enforcement path.
- **Only a credential-shaped patch holds for a person.** apply-patch escalates a credential shape in an issue patch or a patched blob as the new `patch-credential` reason, ahead of every `-invalid` refusal (a SHA-256 mismatch, an extra file beside the patch, a symlink, the path count, a blob's size; a patch made on another commit; each blob is read whole before its size is refused), with the token shapes it shares with the read runner's scan job (`lib/publish-gate.mjs` `CREDENTIAL_SHAPES`), and the issue lane holds it as `security-risk`. Any other `patch-invalid` now retries like `patch-apply-failed`. Rows other than `issue` keep escalating their `-invalid` reason for a credential shape.

### Fixed

- **A trusted size-split child admission takes at Size large is no longer skipped as `split-required`.** `trustedSplitChild`, which feeds the issue lane's `split-child` fact, applies `splitChildBody` exactly as admission does; it no longer also refuses a child whose parent body someone else last edited when the child's lines come from a listed human's comment.
