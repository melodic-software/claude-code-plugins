---
bump: patch
---

### Changed

- The review evidence check also clears a read-only workflow whose `name:` is its file stem in Title Case (hyphens to spaces, PR, CI, API and WIP upper case), beside the stem form, so a repository on either convention clears it and no `workflow_run` listener naming another workflow fires on it.
