---
bump: minor
---

### Changed

- In the merge queue, `ci-status` now holds a pull request whose author pr-verify judges under `merge.verify-authors` but is not the lanes App (with `lane-or-owner`, any account on the trusted-actor list) when pr-verify's verdict reader reports a FAIL for its head: `verify:fail`, `verify:earlier-fail` or `verify:repeated-fail` (owner decision 2026-11-04, "Hold on FAIL only (Recommended)"). Before, such a pull request queued on the owner's credentials merged with no verdict read. No pass, a stale or untrusted-spec pass, `verify:unreadable` and `verify:too-old` do not hold it, and a trusted approval of the head lifts the hold. The lanes App's holds are unchanged, and the kill switch, member veto, hold paths, cost paths and trusted-actor list holds stay the lanes App's alone. Authors pr-verify does not judge, Dependabot's included, merge as before.
