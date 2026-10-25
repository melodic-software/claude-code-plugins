---
bump: minor
---

### Added

- `address-feedback` works a session PR, one a trusted person opened, while a `lanes-may-fix` label whose newest `labeled` event a trusted person made is on it; never past `do-not-merge` or a `Hold:` body line (owner rule, 2026-10-24). The new `adoption.feedback-idle-minutes` key also lets it work an unlabeled session PR once its head was pushed that many minutes ago; this repository leaves it unset, so that path is off pending the owner's choice. The half-hourly sweep takes such a PR whose head no round has worked, at most one dispatch per tick. A session push while the lane works supersedes the lane's patch instead of being overwritten (`.github/scripts/pr-unblock/feedback-dispatch.mjs`).
- `apply-patch` moves a PR branch with a compare-and-swap from the gated head (GraphQL `updateRefs` with `beforeOid`), so a branch force-pushed back to an ancestor while the patch was built is never re-grown. A `Hold:` body line set while the model worked now holds the patch on a PR the lanes App did not open. A session PR labeled `needs-human` is held from `address-feedback`. A session head the gate refused with `untrusted-trigger` is not swept again.
