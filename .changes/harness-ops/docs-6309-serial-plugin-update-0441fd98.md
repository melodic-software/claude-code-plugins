---
bump: patch
---

### Changed

- `context/gotchas.md` records why the user sweep stays serial: concurrent `claude plugin update` and `plugin uninstall` calls lose registry writes while exiting 0 (probe on Claude Code 2.1.310, #6309).
