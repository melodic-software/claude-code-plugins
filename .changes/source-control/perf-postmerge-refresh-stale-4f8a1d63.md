---
bump: patch
---

### Changed

- The pr-merge gate no longer reuses a shared post-merge answer that passes with a lane merge still unverified once that answer is over two minutes old (`SHARED_UNVERIFIED_MAX_AGE`, timed from its recorded `computedAt`): it runs the post-merge check again, as it already did on a new lane merge. Every recompute, stale or new-merge, is written back to the `--postmerge-result` file atomically in the same schema, so the next candidate reuses it; a failed write is logged and the verdict stands. What counts as verified, charged or refused is unchanged: only a passed verifying run clears the in-flight refusal.
