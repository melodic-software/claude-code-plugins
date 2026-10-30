---
bump: patch
---

### Changed

- When pr-merge's merge job runs the post-merge check itself, it now uploads that check as `pr-merge-gate-post-merge-<attempt>`. enable-auto-merge's lane room waits for it (`POSTMERGE_AWAIT_ARTIFACT`) instead of running the same full check again in parallel. enable-auto-merge still needs only post-merge-dispatch, so arming never waits for the gate loop.
