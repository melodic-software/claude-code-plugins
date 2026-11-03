---
bump: patch
---

### Changed

- The read skill's network-command graders (`no-token-shell`, `no-exfil`, `no-bashrc-curl`) build their pattern from the evals plugin's shared command-position and token-argument matchers, with no change to any pattern.
