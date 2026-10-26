---
bump: minor
---

### Added

- The interview surface has a `propose` op for a new question an Ask opens: `id`, `title`, `short`, optional `group` and `fromSeq` (the Ask it answers). The question is `proposed` until the user answers it: the page shows a Needs-you card, `Claude proposes adding: <title>`, with Accept, Edit and Not this and no Decide list, which post a `proposal` event (`accept`, `edit` with the user's wording, or `decline`). The server derives the question `open` after an accept or edit and `archived` after a decline, and refuses a decision on it before then, and an accept until Claude writes its recommendation. The exports write no row for it until the user accepts or edits it (a declined one exports as a withdrawn row), `status` lists it apart from the live count, and a recommendation, alternatives, commitments or a terminal answer on it are refused until then.
- The interview skill's surface guide says a reply to an Ask that opens new scope carries an `Understood as:` readback naming the proposed ids, and a question an Ask opens goes through `propose` before it gets a recommendation.
