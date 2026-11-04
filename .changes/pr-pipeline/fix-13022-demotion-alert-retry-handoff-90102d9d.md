---
bump: patch
---

### Fixed

- A fix or quarantine issue the post-merge demotion alert could not hand to intake triage no longer takes `needs-human`. A fix issue gets a hidden marker comment on it and on its record, a quarantine issue one on the issue, and each alert run retries what a marker names until it succeeds. A record still takes `needs-human` when a failing check was over the cap or outside the name charset.
