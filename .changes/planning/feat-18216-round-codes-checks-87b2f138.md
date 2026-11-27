---
bump: minor
---

### Added

- `scripts/check-round-codes.sh` adds three deterministic interview-round checks: under `--pacing single`, it fails a `Later:` topic that matches another question title in the round or open in the ledger (`preview=<line>:later:<Qid>`) and flags Context or Alternatives word overlap with another question title (`preview=<line>:overlap:<Qid>`); for every `My recommendation:` question, it requires a checkable basis (`basis=<line>:missing`, `basis=<line>:uncheckable`), a confirmable `Flips if:` / `Would change if:` condition (`flips-if=<line>:uncheckable`), and a flip condition when Context names an open or unknown fact (`missing=<line>:flips-if`); and its `undefined=` term check now covers terms defined in another question's `Context:` in addition to the ledger's `## Terminology matrix`.
