---
bump: patch
---

### Security

- The guard decision log now redacts a stateless GitHub App installation token (`ghs_` followed by a JWT, with no app id) whole, where it used to leave the JWT payload and signature in the record, using GitHub's recommended `ghs_` regex.
