---
bump: minor
---

### Added

- `/harness-config:audit` reports each suppression entry, at every layer, whose `date` is older than `exceptions.max_days` as a Category K `suppression-age` warning that names the entry, its reason and its age. The default is 90 days, per ADR 0080; set `exceptions.max_days` in `docs/conventions/harness-config.yaml` for another value. The entry keeps suppressing and nothing is removed. The schema accepts the new `exceptions.max_days` key.
