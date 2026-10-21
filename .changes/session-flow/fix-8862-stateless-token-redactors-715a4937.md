---
bump: patch
---

### Security

- The running-retro observer now redacts a stateless GitHub App installation token (`ghs_` followed by a JWT, with no app id) whole, where it used to leave the JWT payload and signature in its output; the save-point secret scan flags it whole. Both use GitHub's recommended `ghs_` regex.
