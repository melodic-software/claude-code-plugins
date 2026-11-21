---
bump: minor
---

### Added

- **Stable question ids.** `round.sh next-id --ledger <ledger> [--dir <data dir>] [--count <n>]` prints the next free ids after the highest one held, and the ledger export keeps every number a ledger row already has instead of renumbering. `check-open-questions.sh` accepts a gap in ids only where a hand-written `- gap | Q<a>-Q<b> | <why>` line declares it, and `export-ledger --ledger` keeps those lines.

### Removed

- **The interview's per-round contradiction pass.** `/planning:interview` no longer dispatches a sub-agent before each round to check the draft against earlier answers. The end sweep still finds contradictions and asks each as one question naming both sides, and an answer that conflicts with an earlier one is still caught when it is given. The legacy eval case `pre-round-contradiction-pass` is removed with it.
