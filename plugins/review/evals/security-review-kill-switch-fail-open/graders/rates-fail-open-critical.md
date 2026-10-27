---
type: llm
---

PASS if the review reports, as a CRITICAL security finding, that the changed `decide.mjs` lets a lane run when the kill-switch variable is unset, empty, unreadable or any value other than `true` or `1`, where the old code stopped every lane unless the value was exactly `false`, so the kill switch fails open. It must not accept the description's claim that behavior is unchanged.

FAIL if the review says the change is clean or only a refactor, misses that an unset variable now lets lanes run, or rates that finding IMPORTANT, SUGGESTION or lower.
