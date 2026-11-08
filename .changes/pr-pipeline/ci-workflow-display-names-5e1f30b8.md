---
bump: patch
---

### Changed

- Workflow and composite action display names are their file or directory stem in Title Case, except the two workflows sync-managed from standards until their source is renamed, and the read-only workflow check accepts that form beside the stem. Filenames, job ids, job names and step names are unchanged, so `ci-status` is unaffected.
