---
bump: patch
---

### Security

- The publish gate keeps a view local (and refuses the hosted page) when it carries an npm, Google API, Pulumi or Azure storage key, a JWT, Docker registry auth, a base64-encoded PEM block or a netrc password.
- netrc passwords are caught in the `default` entry and on a `password` line of their own.
