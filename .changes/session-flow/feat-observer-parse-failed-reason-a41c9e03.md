---
bump: minor
---

### Added

- Observer `parse_failed` usage rows, check and gate, record why the reply was rejected (`reason`: `no_finding`, `no_rule`, `bad_category` or `field_too_long:<field>`) and, when the reply had a finding, the `lengths` of its finding, rule and evidence; the reply text is never recorded.
