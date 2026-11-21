---
bump: minor
---

### Added

- `/work-items:track add --session-owned`: the ownership choice for a session filing work it will do itself. It applies the session-owned role label, resolved from `config.role_labels["session-owned"]` (default `session-owned`) as the human-gated role label is, so the software-factory lanes skip the item, and it leaves off the `needs-triage` floor. It cannot be combined with `--agent-ready`, and a label missing from the live set stops the action before anything is created.
