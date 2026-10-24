---
bump: patch
---

### Changed

- The vendored git-hook installer (`lib/git-hooks/install.mjs`) accepts an optional `remote` block in `git-hooks/entries.json` and a `plan --scope remote` that returns a lefthook `remotes:` entry for it; a plugin without the block behaves as before, and `copy --scope remote` is a usage error.
