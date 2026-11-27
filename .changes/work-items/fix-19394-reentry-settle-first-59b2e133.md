---
bump: patch
---

### Fixed

- `/work-items:triage --ci` quotes a recorded decision and treats what it answers as settled before it looks for what the decision leaves open. A step the decision reserves to a person is stated after the quote with `needs-human`, not listed as an open question, and a point the decision answers is never asked again, even as a recommendation.
