---
bump: patch
---

### Fixed

- `/review:explain-change` hosted publish: when the page recorded in the sidecar was deleted outside the skill, the failed replace is retried once as a create, so a rebuild publishes a new page and the sidecar takes its id instead of the publish failing. (#6749)
