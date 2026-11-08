---
bump: patch
---

### Changed

- The review evidence check clears a read-only workflow only when its `name:` is its file stem in Title Case (hyphens to spaces, PR, CI, API and WIP upper case), so no `workflow_run` listener naming another workflow fires on it. A repository whose workflows still name themselves by stem no longer clears that check until it uses the new names.
