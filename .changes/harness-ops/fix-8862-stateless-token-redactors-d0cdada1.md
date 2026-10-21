---
bump: patch
---

### Security

- The machine profile now refuses a stateless GitHub App installation token (`ghs_` followed by a JWT, with no app id) as a record value, using GitHub's recommended `ghs_` regex.
