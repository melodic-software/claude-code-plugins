---
bump: minor
---

### Added

- `/planning:interview` checks at every round boundary whether the work is bigger than it looked, on two triggers (the context-guard zone report has worsened, or two rounds running opened more questions than they closed), and recommends `/planning:wayfind chart` with the ledger, constraints, starting-point disclosure and shorthand glossary carried over. The interview ledger gains a `## Starting point` section, so the intake disclosure survives a `/clear` before wayfind charts. It also takes a "this is small, ship it" exit at any round boundary: remaining open questions are deferred with the operator's reply as the reason and tagged `USER-RESERVED`, the Step 3 confirmation and the Step 4 `--brief` check still run, and the work hands off to `/implementation:implement`. The rules live in the interview's new `context/routing.md`.
- The interview states why its entry gate is diff size and retry cost rather than behavior change.
