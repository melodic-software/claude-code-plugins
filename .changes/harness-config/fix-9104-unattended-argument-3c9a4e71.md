---
bump: minor
---

### Added

- `/harness-config:draft-auto-mode-rules`, `/harness-config:audit-permission-state` and `/harness-config:audit-permission-grants` take an optional `--unattended` modifier, accepted anywhere in their arguments. With it, the run records its native offer (`/auto-mode-setup` or `/permissions`) in its output instead of asking; without it, the run asks. The argument hints list it, and neither audit passes it to its script.
