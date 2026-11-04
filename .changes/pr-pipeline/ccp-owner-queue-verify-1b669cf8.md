---
bump: minor
---

### Changed

- In the merge queue, `ci-status` now holds every pull request whose author pr-verify judges under `merge.verify-authors` (with `lane-or-owner`, the lanes App and every account on the trusted-actor list) on the verifier holds: a pr-verify pass at the head, the link it judged, and no FAIL the verdict reader counts. Before, only the lanes App's pull requests were held, so an owner pull request queued on the owner's credentials merged with no verdict read. The kill switch, member veto, hold paths, cost paths and trusted-actor list holds stay the lanes App's alone. Authors pr-verify does not judge, Dependabot's included, merge as before.
