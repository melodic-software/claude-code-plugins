---
bump: patch
---

### Fixed

- The pr-merge gate (`babysit_verify_evidence`) no longer refuses a head `verify:fail` for ever after a relink: a FAIL at a head is superseded when every counted FAIL there is the pull request's own, every counted pass there was created after them and records other linked issues, and from the FAIL's creation to each pass run's completion the pull request has at least one body edit or issue connect or disconnect, every one by a trusted human. The lanes App or any other Bot, an unnamed actor, a failed or cut read, or the same linked issues keep the FAIL. A superseded FAIL still counts toward the FAIL cap, and a merge-only head carries a FAIL forward unless it was superseded at its own head.
