---
bump: patch
---

### Fixed

- **A live-prototype restart no longer fails when the stopped server has not released its ports yet.** `restart` now waits up to 5 seconds for the kept guest and control ports to free (`SHARED_PORT_FREE_SECONDS` overrides), and refuses with a message naming the port when one stays busy ([#18551](https://github.com/melodic-software/claude-code-plugins/issues/18551)).
