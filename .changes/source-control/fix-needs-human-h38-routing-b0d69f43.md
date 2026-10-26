---
bump: minor
---

### Changed

- The merge gate pulls a person in only for a reason a person must clear (owner rule 2026-10-26): `babysit_risk.person_reasons` (`PERSON_CODES`: a CRITICAL security finding, a trusted-actor widening, a cost hold, every high path, and `files-capped`, a listing past the files API's 3000-file cap) is the one list the gate and `enable-auto-merge.mjs` read. A risk hold the lanes clear, such as review evidence not bound to the head or a listing a read did not finish, keeps its reasons comment and no longer gets the human-gated label however long it stands.
- A blocking security finding a bound review left open holds as `security-finding` after the lane unbinds (a new head, a newer marker, a retargeted base): the binder carries the count from the newest head of the pull request the security lane's evidence binds at, from the runs, comments and threads it already read.
- `babysit_verify_evidence.NEEDS_HUMAN` drops `verify:spec-changed`, which the lanes judge again; the terminal repeated-FAIL cap, `verify:too-old` and `verify:untrusted-spec` stay a person's.
- `evidence --lane-reviews` reports `reviewsPerson`, whether only a person clears the risk hold it names.

### Fixed

- The merge gate re-runs a rate-limited AI review only when the run's attempt 1 concluded `failure`, the condition under which the review binding takes attempt 2, so a re-run never spends the one allowed attempt on a hold.
