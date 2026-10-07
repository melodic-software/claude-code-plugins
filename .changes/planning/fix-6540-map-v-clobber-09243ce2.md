---
bump: patch
---

### Fixed

- **`scripts/fetch-docs.sh` keeps a map lookup's value in the caller's own variable
  ([#6540](https://github.com/melodic-software/claude-code-plugins/issues/6540)).** Under
  `--public-only`, the address check during an origin's `llms.txt` fetch no longer overwrites the
  "no bundle" result, so an origin without `llms.txt` is never given a bundle channel.
