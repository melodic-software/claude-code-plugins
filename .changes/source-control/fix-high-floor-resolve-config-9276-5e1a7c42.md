---
bump: patch
---

### Changed

- The HIGH path floor also holds `.github/actions/resolve-config/**`, so a change there scores HIGH and waits for the owner: the token broker runs that directory's code from main in its signer process.
