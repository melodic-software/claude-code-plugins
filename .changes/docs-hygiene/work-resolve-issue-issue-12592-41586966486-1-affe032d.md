---
bump: minor
---

### Changed

- `/docs-hygiene:rename-references` apply mode no longer asks before applying the Certain bucket.
  It applies those matches by default and reports the count, one or two example matches, and how
  to review the bucket one match at a time instead. The proceed/abort gate, the Chain-context
  prompt and the per-match Ambiguous prompts are unchanged. (#12592)
