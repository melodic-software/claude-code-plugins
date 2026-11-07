---
bump: patch
---

### Fixed

- The PR capture's key proxy allows the `fallback-credit-2` beta, which Claude Code sends on some requests. The proxy refused it with a 403, so those captures failed at "Check the probe".
