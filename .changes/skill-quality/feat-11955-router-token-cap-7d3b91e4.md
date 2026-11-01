---
bump: minor
---

### Added

- Check 30 warns when a SKILL.md runs above 5,000 tokens, the router cap `/playbooks:skill-authoring` sets. The count is an estimate (bytes / 4 over the whole file), and the check prints it as INFO when the file is at or under the cap.
