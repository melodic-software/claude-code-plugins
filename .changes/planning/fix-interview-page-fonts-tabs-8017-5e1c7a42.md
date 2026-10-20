---
bump: patch
---

### Fixed

- The interview page names only fonts it can load under its same-origin CSP, so the declared IBM Plex and Newsreader faces no longer silently fall through. The side-panel tabs follow the WAI-ARIA tabs pattern: Left, Right, Home and End move between tabs and only the selected tab is in the tab order. The summary omits the Decisions table when no question is answered. The status pill shows a neutral Connecting state until the first connection attempt fails instead of flashing red.
