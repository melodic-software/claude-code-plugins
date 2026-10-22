---
bump: minor
---

### Changed

- The pr-merge lane adopts a pull request any trusted-actor-list account opened, a `User` or a
  `Bot`, read at the default branch head (owner decision 2026-10-22); a `Bot`'s needs no idle
  window. pr-merge.yml lists each listed account's PRs by login. Without `adoption.idle-hours`
  nothing is adopted.
- For an adopted pull request a person opened, the HIGH path floor and the manifest review score
  only paths that non-merge commits by someone other than its author touched, so the person's own
  lines need no person while a lane's fix to a floor path still holds. An App's pull request, or
  an unreadable commit list, scores every path.
