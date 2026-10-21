---
bump: patch
---

### Fixed

- The shared page's browser suites run 6 at a time again under CI. The local default stays 2, which protects the host's memory; at 2 the suites ran past the CI leg's time limit.
