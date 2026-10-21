---
bump: patch
---

### Removed

- The lanes launcher's cloud stage-start probe no longer tells the session to put the `<!-- execution-target:fallback v1 -->` marker comment on the item. No per-item dispatcher reads it; the session still sets `execution_target_fallback` in the lane's telemetry state block.
