---
bump: patch
---

### Security

- `/bugs:scan` no longer runs the scanned repository's code on an unattended run: hunters and verification gates get `execute: none`, run no test, script or invocation, and the gate labels each surviving finding `verified-by-reading`. On an interactive run the scan asks the person once, before the hunters, and checks run only after an explicit yes from that person. The report's run metadata names the permission ([#7787](https://github.com/melodic-software/claude-code-plugins/issues/7787)).
