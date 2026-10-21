---
bump: patch
---

### Security

- The settings audit matches stateless GitHub App installation tokens (`ghs_` followed by a JWT, with no app id) with GitHub's recommended `ghs_` regex.
