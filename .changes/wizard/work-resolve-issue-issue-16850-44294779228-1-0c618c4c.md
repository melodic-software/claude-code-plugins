---
bump: patch
---

### Changed

- `/wizard:unattended` no longer restates how `Get-Secret` searches vaults, what `-AsPlainText` converts, or when the Keychain and `gpg` prompt. It keeps what the script does (no `-Vault`, strings only, the first line of `pass show`) and the pre-run unlock steps, and points to the `Get-Secret`, SecretStore, `security` and `pass` pages for the rest.
