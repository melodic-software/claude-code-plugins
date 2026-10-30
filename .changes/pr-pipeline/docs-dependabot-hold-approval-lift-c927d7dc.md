---
bump: patch
---

### Fixed

- **The README now says how a held Dependabot pull request is released.** ci-status's trust-path hold on a Dependabot pull request clears when a person on the trusted-actor `human` list approves the current head; a new push needs a new approval. The README no longer calls the admin bypass a break-glass, since the ruleset requires ci-status and the merge queue even for an admin merge.
