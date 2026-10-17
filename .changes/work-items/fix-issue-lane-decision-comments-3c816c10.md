---
bump: patch
---

### Fixed

- `/work-items:work` CI mode reads the trusted comments the issue lane now passes in `issue.json`: a listed maintainer's recorded decision settles the matching open question in the body, so only a question no such comment answers is a reason to push back, and a recorded keep-`Refs` decision sets `"link": "refs"` in the outcome.
- `/work-items:attend-queue` updates the item body's open-question section after writing an escalation answer back, so the issue states its own decision.
