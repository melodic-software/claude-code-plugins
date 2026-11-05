---
bump: minor
---

### Removed

- `/attribution:audit` no longer reads the repository's `.claude/attribution.json` and
  `.claude/attribution.local.json`. The team layer and personal override are
  `<home>/attribution.yaml` and `<home>/attribution.local.yaml` only, read since 0.12.0. The
  user-global `~/.claude/attribution.json` layer is unchanged.

### Changed

- `/attribution:setup check` reports an old `.claude/attribution.json` or
  `.claude/attribution.local.json` as a retired config to migrate (records `attribution-r003` and
  `attribution-r004`), and `apply` carries its keys into the YAML before cleaning it.
