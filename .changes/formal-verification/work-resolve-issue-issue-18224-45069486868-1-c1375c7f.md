---
bump: patch
---

### Fixed

- `/formal-verification:chart` runs on native Windows: it reads TLC output with CRLF line ends the same as LF, cleans up through Node instead of `/bin/sh`, opens no console window for Java, and sets `TEMP` and `TMP` for the check. The skill's native-Windows run line defers to the launcher's Node version gate.
- A parent state with one way in gets one arrow to the parent and a start marker to each child.
- A spec SANY cannot read reports SANY's line and column, not a Java stack trace.
