---
bump: minor
---

### Changed

- The self-answer step reads prior owner decisions first: the repository's declared owner-decisions record and earlier interview ledgers. A quoted ruling that covers the question answers it, so a decided question is not asked again.
- `/planning:interview` no longer asks a decision whose evidence leaves only one viable answer. The round header names it on a `Settled by evidence:` line with its Basis, its register row records it as `answered-from-evidence`, and the user can reopen it by id. Every decision with a live alternative is still asked.
- The shared interview lane says it is not for regulated or confidential topics until guests sign in.
