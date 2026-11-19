---
bump: patch
---

### Fixed

- The format and lint git-hook entries start pwsh without the PATH entries on a 9p mount (the Windows host's directories under WSL), where PSScriptAnalyzer's command lookups made a commit touching two large scripts take over a minute.
