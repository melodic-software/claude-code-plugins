---
bump: patch
---

- `/work-items:triage --ci` reads what a recorded decision opens, not only what it settles. A step the decision reserves to a person (the author runs or approves something first) takes `needs-human` with `needs_human` false, even where a rule says a done-when item a lane run cannot do needs no person. A term the decision adds that leaves a set or value undefined becomes a new open question with a `RECOMMENDED:` answer, never a choice the run makes itself.
