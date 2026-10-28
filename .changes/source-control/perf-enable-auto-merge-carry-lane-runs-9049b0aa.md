---
bump: patch
---

### Changed

- `/source-control:babysit-prs` merge gates (pr-merge.yml): a completed review-lane run's attempts, jobs and annotations come from the run cache, carried between scheduled pr-merge runs, while the live run listing still shows that same completed attempt, instead of being read from GitHub on every tick. This cuts about 42 of the 77 GITHUB_TOKEN calls an enable-auto-merge run makes.
