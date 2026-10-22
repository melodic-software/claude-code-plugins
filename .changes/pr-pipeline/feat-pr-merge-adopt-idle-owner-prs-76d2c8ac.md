---
bump: minor
---

### Added

- `merge.verify-authors: lane-or-owner` judges the lanes App's pull requests and the owner
  account's, matched by account id, so an idle owner pull request the pr-merge lane adopts has a
  verdict. This repository sets it.

### Changed

- The verifier's spec now counts text a trusted human wrote even when that human opened the
  pull request, so an owner pull request whose closing issue the owner wrote is judged against
  that issue. Text by the lanes App, any other Bot or App, or an untrusted account is still left
  out.
