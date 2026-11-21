---
bump: patch
---

### Fixed

- pr-dispatch-feedback's event path ends green with a `skip:` line when a lane comment's run is still going, instead of failing the job. pr-unblock-dispatch's sweep decides that pull request again on its next tick.
