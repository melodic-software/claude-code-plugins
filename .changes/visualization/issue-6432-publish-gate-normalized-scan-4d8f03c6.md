---
bump: patch
---

### Fixed

- The publish gate also scans a normalized copy of each line (tags removed, HTML entities decoded, doubled backslashes folded), so a credential or machine path that is tag-split, HTML-escaped or JSON-escaped is refused or routed before upload, as the pages host already does.
