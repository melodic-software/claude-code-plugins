---
bump: patch
---

### Changed

- In a repository whose pipeline file sets `models.issue-status`, the merge path writes no issue status label. A capped close that parks an issue sets its Work status field to `confirmed` and no longer adds `status: confirmed` or removes `status: ready`. A demotion record whose field write fails is reported as an error, and `needs-human` is no longer added in its place; a later pass sets the field on an open record that still holds no Work status value, and leaves any value already set. Closing a lifted record still removes a `needs-human` label filed before the repository set `models.issue-status`. A repository without `models.issue-status` keeps the label writes it had. `agent-ready` writes are unchanged.
- A park's Work status write now fails when GitHub keeps an option other than `confirmed`. Before, any successful call counted as written.
