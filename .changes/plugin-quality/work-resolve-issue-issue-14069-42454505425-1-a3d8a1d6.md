---
bump: patch
---

### Changed

- The audit's research gate takes its two labels from the target repository's tracker binding, `config.role_labels` in `work-items.yaml`. A suggested change that cleared research files under the `autonomous-eligible` role (default: `agent-ready`), and any other under the `owner-decision` role (default: `status: needs-decision`).
