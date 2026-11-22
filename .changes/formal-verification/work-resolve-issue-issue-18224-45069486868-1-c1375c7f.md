---
bump: patch
---

### Fixed

- `/formal-verification:chart` runs on native Windows: it reads TLC output with CRLF line ends the same as LF, cleans up through Node instead of `/bin/sh`, opens no console window for Java, and sets `TEMP` and `TMP` for the check.
- A parent state with one way in gets one arrow to the parent and a start marker to each child.
- A spec SANY cannot read reports SANY's line and column, not a Java stack trace.
