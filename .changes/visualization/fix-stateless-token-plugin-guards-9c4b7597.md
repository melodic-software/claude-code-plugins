---
bump: patch
---

### Security

- Credential guards now catch stateless GitHub App installation tokens (`ghs_` followed by a JWT), using GitHub's recommended `ghs_` regex where a guard matches the whole token.
