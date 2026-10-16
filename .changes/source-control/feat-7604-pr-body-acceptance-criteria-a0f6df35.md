---
bump: minor
---

### Added

- `/source-control:pull-request create` copies the plan Brief's acceptance criteria into an `## Acceptance criteria` section of the PR body when the branch implements a plan: a caller-named `PLAN.md` or topic slug, else the slug derived from the branch, else the single `PLAN.md` in the memory directory. The section states values only, never a path into the memory directory.
