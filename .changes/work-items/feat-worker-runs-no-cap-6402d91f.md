---
bump: minor
---

### Changed

- `/work-items:work --ci` keeps a progress note, `.lane-progress.md` at the checkout root, while it works: it rewrites the note (Done, In progress, Next steps, Decisions, Dead ends) as it finishes each part, reads it first when it resumes an earlier run's branch, and deletes it in the change it reports done, so a long issue run carries its context from one job to the next.
