---
bump: patch
---

### Changed

- In a repository whose pipeline file sets `models.issue-status`, the merge path writes no issue status label. A capped close that parks an issue sets its Work status field to `confirmed` and no longer adds `status: confirmed` or removes `status: ready`. A demotion record whose field write fails is reported as an error, and `needs-human` is no longer added in its place. Closing a lifted record no longer removes `needs-human`, because closing the record ends its hold. A repository without `models.issue-status` keeps the label writes it had. `agent-ready` writes are unchanged.
- A park's Work status write now fails when GitHub keeps an option other than `confirmed`. Before, any successful call counted as written.
