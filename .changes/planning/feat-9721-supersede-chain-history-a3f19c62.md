---
bump: minor
---

### Added

- **Interview page: a re-issued question keeps its history across supersede chains (G6).** The server derives `supersedesChain` on a question that supersedes another, listing every earlier question of the chain, first asked first, with its round and, when set, its stage. It is never written to `questions.json`. The detail pane shows the whole chain, for example `Asked as Q5 in round 2, then Q35 in round 4`, where it used to link only the question it replaced.
- **`add`, `add-round` and `apply` warn on a one-for-one mass supersede.** A write that supersedes three or more questions one for one names up to five of the pairs and points to `revise`, which keeps a question's id, thread and answer.

### Changed

- **The carried-rounds count starts from the chain's first question.** The `asked N rounds ago, unanswered` chip and the "Still open from earlier rounds" section count from the round the question was first asked in its stage. Before, a question re-issued in round 5 counted as new in round 5.
- **"Still open from earlier rounds" is pinned in every view, not only Rounds.** Groups and Tree pin a copy at the top of the rail and keep each question in its group or its place in the tree.
- **`archive` clears any hold on the questions it archives.** It removes `waiting`, `waitsOn`, `waitingBy` and `waitingSince` and adds a `No longer ...` history line, as `wait` with `clear` does. An archived question no longer carries a `waiting` hold.
