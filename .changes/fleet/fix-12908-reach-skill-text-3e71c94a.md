---
bump: patch
---

### Fixed

- `/fleet:reach` says a lane's session listing shows only that lane, so a request naming a machine lists each of its lanes (#12908).
- `/fleet:reach` points a receiver that must stay up at a background session, links the docs section on when a `-p` run ends, and asks for standing instructions that say what to do with each message and when to stop (#12908).
- `/fleet:reach` gives one PowerShell quoting rule, for its PowerShell tool and a PowerShell window alike, that passes an apostrophe intact on Windows PowerShell 5.1 and pwsh 7, in place of `-p "..."`, which 5.1 cuts to its first word (#12908).
