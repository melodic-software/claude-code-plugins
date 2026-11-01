---
bump: patch
---

### Security

- The publish gate keeps a view local (and refuses the hosted page) when it carries an npm, Google API, Pulumi or Azure storage key, URL credentials, a JWT or Docker registry auth.
