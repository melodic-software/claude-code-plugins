---
bump: minor
---

### Added

- `interview` asks in round 1 whether to move to `/planning:wayfind chart` when the opening request itself names unknowns in three or more areas. The user accepts or declines; the interview stays the entry either way, and the fog and question-count triggers still apply after a decline.
- `interview` proposes a qualified name itself when a term it asks about clashes with a concept the code or the glossary already names, adds it to the terminology matrix, and writes the agreed name through the existing vocabulary route under `domain_docs` (new `context/term-clash.md`).
- `interview` asks what a prototype must prove when the outcome feeds one, and splits it into one small piece per question that can be built at once in separate worktrees, recorded as `Prototype <n> proves:` acceptance criteria (new `context/prototype-questions.md`).
- `interview` runs `/discovery:explore` or `/discovery:research` itself when a question turns on a fact, instead of sending the user to find it, and lists such facts in the Brief's captured assumptions tagged `verify during build`.

### Changed

- `interview` states the quick-change skip in one line when invoked on a change whose diff is quick to review and cheap to retry. `context/routing.md` now keeps only the interview's own triggers and thresholds and points to `/session-flow:workflow` for route choice.
