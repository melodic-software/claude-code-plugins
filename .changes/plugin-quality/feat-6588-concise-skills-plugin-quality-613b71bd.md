---
bump: patch
---

### Changed

- The frozen trigger probes for `audit` and `report` name only same-plugin competitors, so a rewrite in another plugin cannot move their scores ([#6588](https://github.com/melodic-software/claude-code-plugins/issues/6588)). Both descriptions are unchanged: in held-out trigger probes on Opus, a shorter `report` description lost one positive query (fired in 21 of 24 positive runs, 23 of 24 before), and the shorter `audit` description could not be measured, because the eval sandbox denied file reads outside it on three negative queries in both versions.
