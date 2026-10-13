---
bump: patch
---

### Fixed

- **The `explore-directions` design record no longer lists an outdated artifacts version floor or an incomplete set of contexts where artifacts are off.** It points at the artifacts page's Availability and design-canvas sections instead, with an as-of date and a recheck trigger.

- **The `detect-ecosystems.sh` wrappers in both skills no longer say `${CLAUDE_PLUGIN_ROOT}` stays literal in an `allowed-tools` rule.** They call the skill-local path a repo convention and point at the skills page's string-substitutions section for which variables a rule substitutes.

### Changed

- **The `design` and `ClaudeDesign` verification records name their probe and drop quoted upstream text.** Binary observations cite the records in `docs/native-surfaces/records.json`; `/design`'s behavior and the settings that remove it are read live from anchored sections.
