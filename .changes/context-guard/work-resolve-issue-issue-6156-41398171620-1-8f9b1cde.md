---
bump: minor
---

### Added

- A malformed `zones.json` (a file that does not parse, or a band shape that fails validation) now shows the person one toast naming the file and the malformed shape, once per distinct file content. Claude gets no line about it, the shipped defaults still apply, and `context_guard_toast` turns it off (#6156).
