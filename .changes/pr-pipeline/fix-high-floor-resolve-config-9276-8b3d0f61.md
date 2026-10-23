---
bump: patch
---

### Changed

- The pr-merge HIGH path floor also holds `.github/actions/resolve-config/**`, so a change there waits for a human merge: the token broker runs that directory's code from main in its signer process.
