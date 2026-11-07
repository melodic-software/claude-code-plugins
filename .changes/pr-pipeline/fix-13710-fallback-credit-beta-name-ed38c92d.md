---
bump: patch
---

### Fixed

- The PR capture's key proxy allows the beta under its real name, `fallback-credit-2026-06-01`. The earlier entry, `fallback-credit-2`, was a truncated reading and matched nothing, so captures still failed at "Check the probe" whenever Claude Code sent the beta.
