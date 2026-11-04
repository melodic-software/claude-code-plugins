---
bump: patch
---

### Changed

- A member's veto comment on a lanes App pull request now also gets the `do-not-merge` label:
  `enable-auto-merge.mjs` adds it on its next reader run, with a `<!-- member-veto-label -->`
  comment just after, and dequeues a queued one. It takes the label off once a later comment by
  each vetoing member lifts the veto, only while the label is that one; a `do-not-merge` the body
  hold, a session or a person added stays. ci-status still fails on the veto comment itself.
