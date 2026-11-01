---
bump: minor
---

### Changed

- `/planning:interview` opens every question with a `Context:` block holding what the decision rests on: the problem, what the source says or ships, what exists today and the gap, and each term defined inline, one claim per line with a link or `file:line` (or a `judgment` label). The one-line context cap is gone. `Basis:` names which Context sources the recommendation rests on, each alternative is its own bullet stating what it gains and what it costs, and an open question shown again keeps its Context, recommendation, basis and alternatives.
- Rounds show every code with its plain name and define each session term inline in each question that uses it; `Checked against:` names constraints in words. Before the first decision question, the interview agrees a terminology matrix with the user, kept in the ledger's new `## Terminology matrix` section.
- `/planning:audit-answers` hands each validator the question's Context block as the evidence the answer rested on.

### Added

- `scripts/check-round-codes.sh` flags a ledger id or session-shorthand term with no name beside it in a drafted round. The interview runs it before each terminal round is shown and keeps each round as `round-<N>.md` in the topic's memory slice.
- The interview page shows a question's `context` field under Context, above the recommendation. `revise` takes `context`, and `add`, `add-round` and `revise` warn when a context carries no link, `file:line` or `judgment` label.
- Eval cases `interview-context-unfamiliar-term-upstream` and `interview-coded-terms-round-answerable`.
