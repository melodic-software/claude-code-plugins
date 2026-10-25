---
bump: patch
---

### Changed

- The derivability follow-up board names other plugins' skills by `/plugin:skill` with a skill-relative path, and the audit-noise shape library names `/harness-config:audit-instructions` instead of a path into that plugin's skill folder.
- The audit-encapsulation skill and its detector spell their example skill roots with a placeholder plugin segment (`plugins/<plugin>/skills/...`, `plugins/*/skills/...`), so the examples no longer read as cites into another plugin.
