---
bump: patch
---

### Security

- Secret-pattern detection now blocks a stateless GitHub App installation token (`ghs_` followed by a JWT, with no app id) whose JWT header holds a `-` or `_`, using GitHub's recommended `ghs_` regex.
