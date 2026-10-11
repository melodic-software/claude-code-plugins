---
bump: minor
---

### Added

- `/work-items:track` gains read actions `view` (an item's title, state, labels and body), `frontier` (items ready to pick, optionally within one container), `changes` (the change requests the tracker links as closing an item) and `labels` (the live label set, or which named labels are missing), and a write action `edit` (title, body, labels, a blocked-by edge, or a comment). `list --parent` lists a container's children, and `add` takes `--label`, `--body-file`, `--parent` and `--blocked-by`. Other plugins call these instead of a tracker's commands (ADR 0060). The GitHub adapter reference gains "Edit title / body", "List labels" and "Linked changes".
