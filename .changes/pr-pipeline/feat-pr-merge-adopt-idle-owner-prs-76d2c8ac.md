---
bump: minor
---

### Added

- `merge.verify-authors: lane-or-owner` judges the lanes App's pull requests and the owner
  account's, matched by account id, so an idle owner pull request the pr-merge lane adopts has a
  verdict. This repository sets it. An adopted owner pull request whose closing issue the owner
  wrote still refuses `verify:untrusted-spec` and waits for a human.
