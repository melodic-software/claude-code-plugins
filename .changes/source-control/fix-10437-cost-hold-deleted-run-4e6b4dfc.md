---
bump: patch
---

### Fixed

- `cost_decision` keeps a cost hold when a lane run of a newer head was deleted. Deleting a run left the older run's notice as the newest, so an older head became the decided head. The decided head now stands only while the head branch's push history (the repository activity API, one page, which deleting a run leaves) shows its push before the decision and a run of every review lane, started before the decision, on each head pushed after that push and before the decision (`unran_head`). A full page or an unreadable history carries nothing.
