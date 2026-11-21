---
bump: minor
---

### Added

- **Stable question ids.** `round.sh next-id --ledger <ledger> [--dir <data dir>] [--count <n>]` prints the next free ids after the highest one held, and the ledger export keeps every number a ledger row already has instead of renumbering. `check-open-questions.sh` accepts a gap in ids only where a hand-written `- gap | Q<a>-Q<b> | <why>` line declares it, and `export-ledger --ledger` keeps those lines. `export-ledger` and `sync-ledger` write `- gap | Q<a>-Q<b> | never assigned` for ids nothing ever held, never for one the ledger held, and a gap line past the last row reserves those ids.
- **Register tags and `round.sh reopen`.** A register row's resolution can end in `kind::`, `problem::`, `depends::`, `reopened::` and `recheck::` tags, which import and export carry unchanged. `round.sh reopen --ledger <ledger> Q<N> --round <n> --fact-file <file>` reopens an answered row under its own number, keeps the old answer and the fact in `## Reopened answers`, and flags every row built on it with `recheck::`, which blocks `check-open-questions.sh` until `reopen --rechecked` clears it.
- **Round detail levels, `scope-check` and `measures`.** `round.sh show --level full|standard|minimal <round-N.md>` prints a saved round at that detail level (full byte for byte; no level hides `Flips if:` or `Commits you to:`), set by the new `question_detail` setting (default `standard`). `round.sh scope-check` prints the counts for a round header's `Scope check:` line, and `round.sh measures` prints rounds, median lines per shown round and reopened answers. `check-round-codes.sh` also fails a question with no single `My recommendation:`, `Withheld:`, `Discovery:` or `Strong answer:` line, and a round header with no `Scope check:` line.

### Removed

- **The interview's per-round contradiction pass.** `/planning:interview` no longer dispatches a sub-agent before each round to check the draft against earlier answers. The end sweep still finds contradictions and asks each as one question naming both sides, and an answer that conflicts with an earlier one is still caught when it is given. The legacy eval case `pre-round-contradiction-pass` is removed with it.
