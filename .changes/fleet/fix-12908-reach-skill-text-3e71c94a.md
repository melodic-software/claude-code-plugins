---
bump: patch
---

### Fixed

- `/fleet:reach` says a lane's session listing shows only that lane, so a request naming a machine lists each of its lanes (#12908).
- `/fleet:reach` says a `-p` receiver lives only as long as its turn, points a long-lived one at a background session, and asks for standing instructions that say what to do with each message and when to stop (#12908).
- `/fleet:reach` gives the PowerShell-window quoting that passes an apostrophe intact on Windows PowerShell 5.1 and pwsh 7, in place of `-p "..."`, which 5.1 cuts to its first word (#12908).
