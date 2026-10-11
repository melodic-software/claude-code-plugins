---
bump: minor
---

### Added

- Interview page: a `reply` or `revise` that changes the recommendation must carry the revised alternatives or `keepAlternatives: true` (CLI `--keep-alternatives`), which states the current ones were checked against it; with neither it is refused and nothing is written. `reply` now takes `alternatives` with `rec`, so an answer and a full revision land in one op, and the history line records whether the alternatives were rewritten or kept (#5801).
- Interview page: `revise` takes `group` (CLI `--group`) to move a question to another existing group in place, keeping its id, thread and answer, with a history line and a warning when either group's summary predates the move; a new `group-order` op reorders the groups, which the Groups rail follows (#5914).

### Fixed

- Interview page: the Rec choice shows the whole recommendation the user accepts, not only its first sentence; the Accept all list keeps its one-sentence preview (#5815).
- Interview page: the revised-recommendation banner says "Recommendation revised." once (a change with no `why` now stores `revised: true`, and data holding the old fallback sentence reads the same), and shrinks to a "Revised" chip, with Previous kept, once the user has opened the question since its latest revision (#5916).
- Interview page: an upstream-pending question names the stale question(s) that cause it, not its direct prerequisites: the server adds a derived `upstreamStale` list (every stale ancestor, nearest first, ties by id; never written), the rail chip reads `Waiting on <them>`, and the banner links them with "Reconfirm … (under Review), or answer this one anyway"; the row is dimmed less and brightens on hover and focus, so it reads as waiting, not locked (#5922).
- Interview page: a question's "needs Qn" chips share one wrapped row under its title instead of one line each, and a met prerequisite carries a check mark labelled "answered" for screen readers, so met and unmet differ by more than colour (#5917).
- Interview page: the stale banner says "Q5 was decided after you answered this" when the prerequisite had no decision before this answer, and "Q5 changed" only when an earlier decision was replaced; the header meter adds "· N to review" (the Review filter's count, which opens that filter) whenever an answered question needs review (#5908).
- Interview page: a stale question whose kept accept predates a change to its own recommendation offers no Reconfirm, since that row would record text the user may not have read; the banner reads "Pick an answer.", `a` arms `Rec` with the revised text, and Previous keeps the old one (#5910).
- Interview page: a save that makes other answers stale takes the user to the first of them in dependency order, switching Show to Review when the current filter hides it, names them in the toast ("Saved Q2. Q3 and Q5 need review; 2 more wait on them."), and `n` visits the rest first; a save that stales nothing navigates as before (#5909).
- Interview page: Claude's latest reply stays in the question's Thread as well as the latest-reply box, so a reply to the user's ask is never shown only above the recommendation, and a reply in the same second as the event it answers sorts after it (#5817).
