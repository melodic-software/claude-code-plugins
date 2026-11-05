---
bump: minor
---

### Changed

- In the merge queue, `ci-status` now holds a pull request whose author pr-verify judges under `merge.verify-authors` but is not the lanes App (with `lane-or-owner`, any account on the trusted-actor list) when pr-verify's verdict reader reports `verify:fail` or `verify:earlier-fail` for its head (owner decisions 2026-11-04, "Hold on FAIL only (Recommended)" and "FAIL holds, cap not (Recommended)"). Before, such a pull request queued on the owner's credentials merged with no verdict read. The repeated-fail cap (`verify:repeated-fail`) only warns; no pass, a stale or untrusted-spec pass, `verify:unreadable` and `verify:too-old` do not hold it. A trusted approval of the head lifts the hold, but an author cannot approve their own pull request, so on an owner-login pull request the lift is a new head that pr-verify passes. The lanes App's holds are unchanged, and the kill switch, member veto, hold paths, cost paths and trusted-actor list holds stay the lanes App's alone. Authors pr-verify does not judge, Dependabot's included, merge as before.
