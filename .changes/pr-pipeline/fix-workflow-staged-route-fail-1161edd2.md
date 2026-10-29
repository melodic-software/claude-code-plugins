---
bump: patch
---

### Fixed

- route workflow-staged to a failing status, not needs-human

  A resolve-conflicts stop on workflow-staged now ends in a failing pr-unblock/conflict status and the lane-stopped comment instead of needs-human. The merge carries the pull request's own .github/workflows/ changes together with the base's, which the lane token cannot push, and nothing in it is a person's decision, so a session merges main by hand. escalation-routes.json routes it fail, and the stopping check skips lane-stopped. clear-escalations.mjs still lifts a workflow-staged label an older lane run set, on the same evidence as before.
