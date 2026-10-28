---
bump: patch
---

### Fixed

- check-wip-cap closes new admissions when it cannot read the base config (a failed resolve-config import, as after a failed `npm ci` of its dependencies), whatever `wip.pause-from` says: `admission-open` is `false`, and `admission_reason` and `admission_basis` are `config-unreadable`, with a `check-wip-cap` warning. Before, the default limits applied with admissions open, so a broken dependency took the queued cap off. The run pause keeps the last known state as before, and a failed `npm ci` still continues, with a warning that says admissions close.
