---
bump: minor
---

### Changed

- **`/planning:wayfind` routes its argument.** An item link, `#<n>` or tracker key works that item on its map; any other text is the topic. A bare call with an open map lists the frontier, recommends one item and waits for the pick.
- **Chart proposes the whole map and waits for one yes** before it creates anything on the tracker: the destination, each item with its type, mode and what it waits on, the Not-yet-specified bullets and the Out-of-scope list.
- **Chart's first question is what done looks like**, recommending a PRD for a coding effort and a decision record or summary otherwise.
- **"I don't know" is a full answer.** Chart sorts each unknown by who can settle it: evidence (a research item, researched before anyone recommends an answer), the user (an interview item), or nobody yet (fog).
- **Chart reads the repository's glossary and work-item conventions** before its first question.
- **Shorter maps.** Notes holds only standing constraints, the skills to consult and the dossier branch link; fog is one labelled bullet per uncertainty; an item body is the question and the criteria an answer must meet.
- **Items are topics.** A decision item is a topic one session can work, with its related questions inside it. Sharp questions that already have a recommendation and wait on nothing are asked in one interview round before the map exists.
