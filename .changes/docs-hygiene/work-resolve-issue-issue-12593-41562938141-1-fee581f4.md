---
bump: minor
---

### Changed

- `rename-references`: the Certain bucket no longer asks through `AskUserQuestion`. It auto-applies by its stated default, and the bucket-count report gives its count, one or two example matches, and how to review it one by one instead (answer the proceed prompt with "review Certain one-by-one"). `context/triage.md`, `context/apply.md` and `SKILL.md` now say the same thing; the Chain-context and Ambiguous buckets and the proceed/abort gate are unchanged (#12593, #12592).
