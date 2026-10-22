---
bump: minor
---

### Changed

- Both interview lanes refuse an alternative that repeats or contains the recommendation (whole words, either way): `round.sh add`, `add-round` and `apply` now refuse what they only warned about, as `reply` and `revise` already did, and the shared session refuses such an alternative in Claude's question input. A `Withheld:` recommendation has nothing to repeat.
- A file written before this keeps loading: the page server flags each restating alternative and the 1:1 page folds it into Accept, now by the same whole-word rule, so an alternative that contains the recommendation folds too.

### Fixed

- A shared session question whose recommendation is withheld no longer shows a "Claude recommends" card: its alternatives stay as cards and its `Withheld:` text shows as the question's open note.
