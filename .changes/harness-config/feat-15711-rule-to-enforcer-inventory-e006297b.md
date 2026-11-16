---
bump: minor
---

### Added

- **Ladder spread in `/harness-config:audit-automation-gaps`.** Present Results prints, read-only
  and with no target, how many of the repository's rules sit on each of the enforcement ladder's
  five tiers, and the guidance rules that forbid a literal a pattern check could match ("sits lower
  than it could", candidates for a person to judge). Both are rollups of one rule-to-enforcer
  inventory that `scripts/rule-inventory.sh` generates, one row per rule (rule, enforcer, rung,
  tier), from the repository's settings, ecosystem records, test files, control skills and
  instruction files. Rung ids and tiers come from the ladder copy the skill carries. A source the
  script cannot find or read is named, never counted as zero, and so is each source present but not
  counted: CI workflows, git hook managers, local settings and enabled plugins' hooks.
- **`rule_inventory.declared` in `harness-config.yaml`.** Rows for rules no file shows, such as a
  type that makes the mistake impossible; the schema describes the key.
