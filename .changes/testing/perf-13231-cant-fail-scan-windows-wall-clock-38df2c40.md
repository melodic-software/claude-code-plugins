---
bump: patch
---

### Changed

- The testing audit's `cant-fail-scan.sh` walks the tree once per run instead of once per pass, and picks each file's adapter without a subshell, so it starts fewer processes, which matters most on Git for Windows (#13231). Its findings and counts are unchanged.
