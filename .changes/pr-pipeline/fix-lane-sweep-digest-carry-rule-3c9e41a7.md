---
bump: patch
---

### Fixed

- The lane sweep digest drops an earlier entry the sweep did not see unless that entry could be unread: its Where workflow is on the collector's `partial` list, a unit of its slice and workflow had findings that were not read, or it names no workflow. Every earlier entry still carries when the collector stopped early or its status, a unit file or a findings file is unreadable. Before, any partly read workflow carried every entry, so the digest only grew. The step summary counts the carried entries by reason.
