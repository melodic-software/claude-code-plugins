---
bump: patch
---

### Fixed

- The comment-tooling eval seed now installs on the hosted eval runner's Python 3.12, where its pinned `tree-sitter` wheels were missing and every seeded case failed at setup.
