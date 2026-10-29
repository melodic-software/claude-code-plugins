---
bump: patch
---

### Fixed

- The hold floor (`babysit_risk.FLOOR_CLASSES`) holds `.github/scripts/pr-unblock/lane-hold.mjs`
  and `.github/scripts/pr-unblock/gate-recheck.mjs` as `enforcement`, beside `gate-source.mjs`, so
  a pull request that changes how a lane hold is read is held like one that changes gate-source
  ([#9419](https://github.com/melodic-software/claude-code-plugins/issues/9419)).
