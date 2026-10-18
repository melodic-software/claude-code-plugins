---
bump: patch
---

### Changed

- `babysit-prs` merge gate: in the pr-merge lane the verdict reader pages the repository's artifact listing once per run instead of once per candidate. When `BABYSIT_VERIFY_LISTING` names a file, the first candidate saves its listing there and later candidates, and their queued-entry checks, read it. A refusal on the saved listing stands; a candidate it would allow is judged again on a listing of its own, which replaces the saved one. A failed listing is never saved, and a missing or malformed file is read from the API. The pr-merge workflow sets the variable for its gate loop. Without it nothing changes.
