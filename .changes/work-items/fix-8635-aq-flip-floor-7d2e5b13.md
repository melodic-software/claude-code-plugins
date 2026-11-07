---
bump: patch
---

### Fixed

- `/work-items:attend-queue` now names the human-floor classes where it keeps an answered escalation gated: only `provenance: untrusted` and `provenance: signal` floor an item, never a structural class or a missing one. Runs had kept a structural-class item gated "if the class is floor" instead of flipping it ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
