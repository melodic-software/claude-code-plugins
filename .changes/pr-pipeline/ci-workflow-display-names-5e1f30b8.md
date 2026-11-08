---
bump: patch
---

### Changed

- Workflow and composite action display names are their file or directory stem in Title Case, and the read-only workflow check compares `name:` to that form. Filenames, job ids, job names and step names are unchanged, so `ci-status` is unaffected.
