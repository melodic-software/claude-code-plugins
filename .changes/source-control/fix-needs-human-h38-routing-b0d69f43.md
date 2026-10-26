---
bump: minor
---

### Changed

- The merge gate pulls a person in only for a reason a person must clear (owner rule 2026-10-26): `babysit_risk.person_reasons` (`PERSON_CODES`: a CRITICAL security finding, a trusted-actor widening, a cost hold and every high path) is the one list the gate and `enable-auto-merge.mjs` read. A risk hold the lanes clear, such as review evidence not bound to the head or an unread listing, keeps its reasons comment and no longer gets the human-gated label however long it stands.
- `babysit_verify_evidence.NEEDS_HUMAN` holds only `verify:untrusted-spec`. `verify:too-old` and `verify:spec-changed` hold for the lanes, and the `verify:repeated-fail` round cap stays but gets its quoting comment with no label.
- `evidence --lane-reviews` reports `reviewsPerson`, whether only a person clears the risk hold it names.

### Fixed

- The merge gate re-runs a rate-limited AI review only when the run's attempt 1 concluded `failure`, the condition under which the review binding takes attempt 2, so a re-run never spends the one allowed attempt on a hold.
