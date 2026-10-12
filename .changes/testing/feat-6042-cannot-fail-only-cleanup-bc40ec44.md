---
bump: minor
---

### Added

- `/testing:cleanup --cannot-fail-only`: for a folder no mutation tool can gate (today .NET), cleanup now offers a mode that deletes only tests that cannot fail, each cleared by a fresh-context skeptic told to find any way the test can fail, behind the per-item yes and the batch approval. It runs no test and proposes no rewrite, merge or quarantine.
