---
bump: minor
---

### Added

- `block-root-delete-target` judges a move and a content destroyer the way it judges a recursive `rm`: one aimed at a root or at HOME is refused, and when the payload carries a cwd the target must sit under the git toplevel or strictly under a temp root, the session scratchpad or an allowed root. That covers each source an `mv` moves away, a move onto `/dev/null` included, each file `truncate` or `shred` names, the file `dd of=` writes, and on the PowerShell tool each `Move-Item` and `Clear-Content` path and a `Set-Content` that writes several files (a comma list, or a wildcard in `-Path`). A `Set-Content` of one file, a `dd` writing to `/dev/null`, and a mechanism named inside quoted prose, such as a `git commit -m` message, stay allowed.
