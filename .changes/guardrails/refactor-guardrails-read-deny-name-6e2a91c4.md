---
bump: major
---

### Changed

- The setup action that writes the credential-file `Read()` deny rules is now `apply read-deny`, in line with the other setup writes that install nothing (`apply identity-domains`). `apply install-read-deny` is no longer an argument; run `apply read-deny` with the same scope, `user` and `remove` arguments.
