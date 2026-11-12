---
bump: major
---

### Removed

- The prerequisite resolver (`skills/setup/scripts/resolve-prerequisites.mjs`) no longer reads a repo-root `.work-item-tracker.json`. The tracker need is present only when `docs/conventions/work-items.yaml` sets a `tracker` mapping; otherwise it is absent, and routines that need the tracker resolve `unsupported`. The absent detail names `/work-items:setup apply` as the fix, and names the JSON file when one is present.

### Changed

- The prerequisite-resolution reference and the backlog-readiness, duplicate-detection, issue-triage and pr-queue-tending routines name only the YAML binding.
