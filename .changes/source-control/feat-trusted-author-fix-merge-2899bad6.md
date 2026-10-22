---
bump: minor
---

### Changed

- The pr-merge lane adopts a pull request any trusted-actor-list account opened, a `User` or a
  `Bot`, read at the default branch head (owner decision 2026-10-22); a `Bot`'s needs no idle
  window. pr-merge.yml lists each listed account's PRs by login. Without `adoption.idle-hours`
  nothing is adopted.
- An adopted pull request closing no issue in this repository is eligible when a person or an App
  in `adoption.spec-from-body-apps` opened it, and the verifier gate accepts a pass that records
  `intent: pull-request` with no closing issue then or now. Any other App still needs its issue.
- For an adopted pull request, the HIGH path floor and the manifest review score only its changed
  paths that a commit not its author's own touched, so a trusted author's own lines, a person's or
  an App's, need no person while a lane's fix to a floor path still holds. A commit is the
  author's own only when GitHub verified it and its author account, and for a person its
  committer account, is the pull request's author. A merge commit not the author's own scores its
  files the pull request changed. The lanes App's own pull requests stay scored whole, and an
  unreadable commit list scores every path.
- A person, whose title and body serve as intent with no closing issue, is a `kind: human` id on
  the trusted list, not any GitHub `User`; the list is read at the default branch head.
