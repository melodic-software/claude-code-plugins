---
bump: patch
---

### Changed

- Trimmed 15 skill frontmatter descriptions (7,409 -> 4,279 chars across changed skills, -3,130c / -42.2%; 11 model-invoked `<= 350c`: `audit-mod-posture` 397 -> 324, `audit-native-overlap` 424 -> 348, `audit-performance` 428 -> 348, `audit-skill-visibility` 432 -> 347, `behavior-probes` 379 -> 329, `changelog` 417 -> 346, `inventory` 373 -> 348, `known-issues` 384 -> 318, `machine-profile` 400 -> 347, `observability` 506 -> 346, `plugins-audit` 420 -> 347; and 4 user-only `disable-model-invocation: true` `<= 150c`: `audit-plugin-landscape` 345 -> 120, `lanes` 988 -> 148, `plugins` 530 -> 120, `setup` 986 -> 143; `control-claude-code`, `audit-install-state`, and `prerequisites` untouched) with zero body changes and zero probe trigger-rate regressions.
